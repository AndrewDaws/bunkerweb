local class		= require "middleclass"
local plugin	= require "bunkerweb.plugin"
local utils     = require "bunkerweb.utils"
local datastore = require "bunkerweb.datastore"
local cjson     = require "cjson"
local captcha   = require "antibot.captcha"
local base64    = require "base64"
local sha256    = require "resty.sha256"
local str       = require "resty.string"
local http      = require "resty.http"
local template	= require "resty.template"

local antibot	= class("antibot", plugin)

function antibot:initialize()
	-- Call parent initialize
	plugin.initialize(self, "antibot")
end

function antibot:access()
	-- Check if access is needed
	if self.variables["USE_ANTIBOT"] == "no" then
		return self:ret(true, "antibot not activated")
	end

	-- Don't go further if client resolved the challenge
	local resolved, err, original_uri = self:challenge_resolved()
	if resolved == nil then
		return self:ret(false, "can't check if challenge is resolved : " .. err)
	end
	if resolved then
		if ngx.ctx.bw.uri == self.variables["ANTIBOT_URI"] then
			return self:ret(true, "client already resolved the challenge", nil, original_uri)
		end
		return self:ret(true, "client already resolved the challenge")
	end

	-- Redirect to challenge page
	if ngx.ctx.bw.uri ~= self.variables["ANTIBOT_URI"] then
		-- Prepare challenge
		local ok, err = self:prepare_challenge()
		if not ok then
			return self:ret(false, "can't prepare challenge : " .. err, ngx.HTTP_INTERNAL_SERVER_ERROR)
		end
		return self:ret(true, "redirecting client to the challenge uri", nil, self.variables["ANTIBOT_URI"])
	end

	-- Display challenge needed
	if ngx.ctx.bw.request_method == "GET" then
		ngx.ctx.bw.antibot_display_content = true
		return self:ret(true, "displaying challenge to client", ngx.OK)
	end

	-- Check challenge
	if ngx.ctx.bw.request_method == "POST" then
		local ok, err, redirect = self:check_challenge()
		if ok == nil then
			return self:ret(false, "check challenge error : " .. err, ngx.HTTP_INTERNAL_SERVER_ERROR)
		elseif not ok then
			self.logger:log(ngx.WARN, "client failed challenge : " .. err)
			local ok, err = self:prepare_challenge()
			if not ok then
				return self:ret(false, "can't prepare challenge : " .. err, ngx.HTTP_INTERNAL_SERVER_ERROR)
			end
		end
		if redirect then
			return self:ret(true, "check challenge redirect : " .. redirect, nil, redirect)
		end
		ngx.ctx.bw.antibot_display_content = true
		return self:ret(true, "displaying challenge to client", ngx.OK)
	end

	-- Method is suspicious, let's deny the request
	return self:ret(true, "unsupported HTTP method for antibot", utils.get_deny_status())
end

function antibot:content()
	-- Check if content is needed
	if not self.variables["USE_ANTIBOT"] or self.variables["USE_ANTIBOT"] == "no" then
		return self:ret(true, "antibot not activated")
	end
	-- Check if display content is needed
	if not ngx.ctx.bw.antibot_display_content then
		return self:ret(true, "display content not needed", nil, "/")
	end
	-- Display content
	local ok, err = self:display_challenge()
	if not ok then
		return self:ret(false, "display challenge error : " .. err)
	end
	return self:ret(true, "content displayed")
end

function antibot:challenge_resolved()
	local session, err, exists, refreshed = utils.get_session()
	if err then
		return nil, "session error : " .. err
	elseif not exists then
		return false, "no session set"
	end
	local ok, err, raw_data = utils.get_session_var("antibot")
	if not raw_data then
		return false, "session is set but no antibot data", nil
	end
	local data = raw_data
	if data.resolved and self.variables["USE_ANTIBOT"] == data.type then
		return true, "challenge resolved", data.original_uri
	end
	return false, "challenge not resolved", data.original_uri
end

function antibot:prepare_challenge()
	local session, err, exists, refreshed = utils.get_session()
	if err then
		return false, "session error : " .. err
	end
	local set_needed = false
	local data = nil
	if exists then
		local ok, err, raw_data = utils.get_session_var("antibot")
		if raw_data then
			data = raw_data
		end
	end
	if not data or data.type ~= self.variables["USE_ANTIBOT"] then
		data = {
			type = self.variables["USE_ANTIBOT"],
			resolved = self.variables["USE_ANTIBOT"] == "cookie",
			original_uri = ngx.ctx.bw.request_uri
		}
		if ngx.ctx.bw.uri == self.variables["ANTIBOT_URI"] then
			data.original_uri = "/"
		end
		set_needed = true
	end
	if not data.resolved then
		if self.variables["USE_ANTIBOT"] == "javascript" then
			data.random = utils.rand(20)
			set_needed = true
		elseif self.variables["USE_ANTIBOT"] == "captcha" then
			local chall_captcha = captcha.new()
			chall_captcha:font("/usr/share/bunkerweb/core/antibot/files/font.ttf")
			chall_captcha:generate()
			data.image = base64.encode(chall_captcha:jpegStr(70))
			data.text = chall_captcha:getStr()
			set_needed = true
		end
	end
	if set_needed then
		local ok, err = utils.set_session_var("antibot", data)
		if not ok then
			return false, "error while setting session antibot : " .. err
		end
	end
	return true, "prepared"
end

function antibot:display_challenge()
	-- Open session
	local session, err, exists, refreshed = utils.get_session()
	if err then
		return false, "can't open session : " .. err
	elseif not exists then
		return false, "no session set"
	end

	-- Get data
	local ok, err, raw_data = utils.get_session_var("antibot")
	if not raw_data then
		return false, "session is set but no data"
	end
	local data = raw_data

	-- Check if session type is equal to antibot type
	if self.variables["USE_ANTIBOT"] ~= data.type then
		return false, "session type is different from antibot type"
	end

	-- Common variables for templates
	local template_vars = {
		antibot_uri = self.variables["ANTIBOT_URI"]
	}

	-- Javascript case
	if self.variables["USE_ANTIBOT"] == "javascript" then
		template_vars.random = data.random
	end

	-- Captcha case
	if self.variables["USE_ANTIBOT"] == "captcha" then
		template_vars.captcha = data.image
	end

	-- reCAPTCHA case
	if self.variables["USE_ANTIBOT"] == "recaptcha" then
		template_vars.recaptcha_sitekey = self.variables["ANTIBOT_RECAPTCHA_SITEKEY"]
	end

	-- hCaptcha case
	if self.variables["USE_ANTIBOT"] == "hcaptcha" then
		template_vars.hcaptcha_sitekey = self.variables["ANTIBOT_HCAPTCHA_SITEKEY"]
	end

	-- Render content
	template.render(self.variables["USE_ANTIBOT"] .. ".html", template_vars)

	return true, "displayed challenge"
end

function antibot:check_challenge()
	-- Open session
	local session, err, exists, refreshed = utils.get_session()
	if err then
		return nil, "can't open session : " .. err, nil
	elseif not exists then
		return false, "no session set"
	end

	-- Get data
	local ok, err, raw_data = utils.get_session_var("antibot")
	if not raw_data then
		return false, "session is set but no data", nil
	end
	local data = raw_data

	-- Check if session type is equal to antibot type
	if self.variables["USE_ANTIBOT"] ~= data.type then
		return nil, "session type is different from antibot type", nil
	end

	local resolved = false
	local err = ""
	local redirect = nil

	-- Javascript case
	if self.variables["USE_ANTIBOT"] == "javascript" then
		ngx.req.read_body()
		local args, err = ngx.req.get_post_args(1)
		if err == "truncated" or not args or not args["challenge"] then
			return nil, "missing challenge arg", nil
		end
		local hash = sha256:new()
		hash:update(data.random .. args["challenge"])
		local digest = hash:final()
		resolved = str.to_hex(digest):find("^0000") ~= nil
		if not resolved then
			return false, "wrong value", nil
		end
		data.resolved = true
		local ok, err = utils.set_session_var("antibot", data)
		if not ok then
			return nil, "error while setting session antibot : " .. err
		end
		return true, "resolved", data.original_uri
	end

	-- Captcha case
	if self.variables["USE_ANTIBOT"] == "captcha" then
		ngx.req.read_body()
		local args, err = ngx.req.get_post_args(1)
		if err == "truncated" or not args or not args["captcha"] then
			return nil, "missing challenge arg", nil
		end
		if data.text ~= args["captcha"] then
			return false, "wrong value", nil
		end
		data.resolved = true
		local ok, err = utils.set_session_var("antibot", data)
		if not ok then
			return nil, "error while setting session antibot : " .. err
		end
		return true, "resolved", data.original_uri
	end

	-- reCAPTCHA case
	if self.variables["USE_ANTIBOT"] == "recaptcha" then
		ngx.req.read_body()
		local args, err = ngx.req.get_post_args(1)
		if err == "truncated" or not args or not args["token"] then
			return nil, "missing challenge arg", nil
		end
		local httpc, err = http.new()
		if not httpc then
			return nil, "can't instantiate http object : " .. err, nil, nil
		end
		local res, err = httpc:request_uri("https://www.google.com/recaptcha/api/siteverify", {
			method = "POST",
			body = "secret=" .. self.variables["ANTIBOT_RECAPTCHA_SECRET"] .. "&response=" .. args["token"] .. "&remoteip=" .. ngx.ctx.bw.remote_addr,
			headers = {
				["Content-Type"] = "application/x-www-form-urlencoded"
			}
		})
		httpc:close()
		if not res then
			return nil, "can't send request to reCAPTCHA API : " .. err, nil
		end
		local ok, rdata = pcall(cjson.decode, res.body)
		if not ok then
			return nil, "error while decoding JSON from reCAPTCHA API : " .. rdata, nil
		end
		if not rdata.success or rdata.score < tonumber(self.variables["ANTIBOT_RECAPTCHA_SCORE"]) then
			return false, "client failed challenge with score " .. tostring(rdata.score), nil
		end
		data.resolved = true
		local ok, err = utils.set_session_var("antibot", data)
		if not ok then
			return nil, "error while setting session antibot : " .. err
		end
		return true, "resolved", data.original_uri
	end

	-- hCaptcha case
	if self.variables["USE_ANTIBOT"] == "hcaptcha" then
		ngx.req.read_body()
		local args, err = ngx.req.get_post_args(1)
		if err == "truncated" or not args or not args["token"] then
			return nil, "missing challenge arg", nil
		end
		local httpc, err = http.new()
		if not httpc then
			return nil, "can't instantiate http object : " .. err, nil, nil
		end
		local res, err = httpc:request_uri("https://hcaptcha.com/siteverify", {
			method = "POST",
			body = "secret=" .. self.variables["ANTIBOT_HCAPTCHA_SECRET"] .. "&response=" .. args["token"] .. "&remoteip=" .. ngx.ctx.bw.remote_addr,
			headers = {
				["Content-Type"] = "application/x-www-form-urlencoded"
			}
		})
		httpc:close()
		if not res then
			return nil, "can't send request to hCaptcha API : " .. err, nil
		end
		local ok, hdata = pcall(cjson.decode, res.body)
		if not ok then
			return nil, "error while decoding JSON from hCaptcha API : " .. data, nil
		end
		if not hdata.success then
			return false, "client failed challenge", nil
		end
		data.resolved = true
		local ok, err = utils.set_session_var("antibot", data)
		if not ok then
			return nil, "error while setting session antibot : " .. err
		end
		return true, "resolved", data.original_uri
	end

	return nil, "unknown", nil
end

return antibot