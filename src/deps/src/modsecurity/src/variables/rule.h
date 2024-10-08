/*
 * ModSecurity, http://www.modsecurity.org/
 * Copyright (c) 2015 - 2021 Trustwave Holdings, Inc. (http://www.trustwave.com/)
 *
 * You may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * If any of the files related to licensing are missing or if you have any
 * other questions related to licensing please contact Trustwave Holdings, Inc.
 * directly using the email address security@modsecurity.org.
 *
 */

#include <string>
#include <vector>
#include <list>

#ifndef SRC_VARIABLES_RULE_H_
#define SRC_VARIABLES_RULE_H_

#include "src/variables/variable.h"
#include "src/actions/severity.h"
#include "src/actions/log_data.h"
#include "src/actions/msg.h"


namespace modsecurity {

class Transaction;
namespace variables {


class Rule_DictElement : public VariableDictElement { \
 public:
    explicit Rule_DictElement(const std::string &dictElement)
        : VariableDictElement(m_rule, dictElement) { }

    static void id(Transaction *t,
        RuleWithActions *rule,
        std::vector<const VariableValue *> *l) {
        RuleWithActions *r = rule;

        while (r && r->m_ruleId == 0) {
            r = r->m_chainedRuleParent;
        }

        if (!r || r->m_ruleId == 0) {
            return;
        }

        addVariableOrigin(m_rule_id, std::to_string(r->m_ruleId), l);
    }


    static void rev(Transaction *t,
        RuleWithActions *rule,
        std::vector<const VariableValue *> *l) {
        RuleWithActions *r = rule;

        while (r && r->m_rev.empty()) {
            r = r->m_chainedRuleParent;
        }

        if (!r) {
            return;
        }

        addVariableOrigin(m_rule_rev, r->m_rev, l);
    }


    static void severity(Transaction *t,
        RuleWithActions *rule,
        std::vector<const VariableValue *> *l) {
        RuleWithActions *r = rule;

        while (r && !r->hasSeverity()) {
            r = r->m_chainedRuleParent;
        }

        if (r && r->hasSeverity()) {
            addVariableOrigin(m_rule_severity, std::to_string(r->severity()), l);
        }
    }


    static void logData(Transaction *t,
        RuleWithActions *rule,
        std::vector<const VariableValue *> *l) {
        RuleWithActions *r = rule;

        while (r && !r->hasLogData()) {
            r = r->m_chainedRuleParent;
        }

        if (r && r->hasLogData()) {
            addVariableOrigin(m_rule_logdata, r->logData(t), l);
        }
    }

    static void msg(Transaction *t,
        RuleWithActions *rule,
        std::vector<const VariableValue *> *l) {
        RuleWithActions *r = rule;

        while (r && !r->hasMsg()) {
            r = r->m_chainedRuleParent;
        }

        if (r && r->hasMsg()) {
            addVariableOrigin(m_rule_msg, r->msg(t), l);
        }
    }

    void evaluate(Transaction *t,
        RuleWithActions *rule,
        std::vector<const VariableValue *> *l) override {
        if (m_dictElement == m_rule_id) {
            id(t, rule, l);
            return;
        }
        if (rule && m_dictElement == m_rule_rev) {
            rev(t, rule, l);
            return;
        }
        if (rule && m_dictElement == m_rule_severity) {
            severity(t, rule, l);
            return;
        }
        if (m_dictElement == m_rule_logdata) {
            logData(t, rule, l);
            return;
        }
        if (m_dictElement == m_rule_msg) {
            msg(t, rule, l);
            return;
        }
    }

    static const std::string m_rule;
    static const std::string m_rule_id;
    static const std::string m_rule_rev;
    static const std::string m_rule_severity;
    static const std::string m_rule_logdata;
    static const std::string m_rule_msg;

private:

    static inline void addVariableOrigin(const std::string &key,
        const std::string &value,
        std::vector<const VariableValue *> *l) {
        auto var = new VariableValue(&m_rule, &key,
            &value
        );
        var->addOrigin();
        l->push_back(var);
    }
};


class Rule_DictElementRegexp : public VariableRegex {
 public:
    explicit Rule_DictElementRegexp(const std::string &regex)
        : VariableRegex("RULE", regex) { }

    void evaluate(Transaction *t,
        RuleWithActions *rule,
        std::vector<const VariableValue *> *l) override {
        if (Utils::regex_search("id", m_r) > 0) {
            Rule_DictElement::id(t, rule, l);
            return;
        }
        if (Utils::regex_search("rev", m_r) > 0) {
            Rule_DictElement::rev(t, rule, l);
            return;
        }
        if (Utils::regex_search("severity", m_r) > 0) {
            Rule_DictElement::severity(t, rule, l);
            return;
        }
        if (Utils::regex_search("logdata", m_r) > 0) {
            Rule_DictElement::logData(t, rule, l);
            return;
        }
        if (Utils::regex_search("msg", m_r) > 0) {
            Rule_DictElement::msg(t, rule, l);
            return;
        }
    }
};


class Rule_NoDictElement : public Variable {
 public:
    explicit Rule_NoDictElement()
        : Variable("RULE") { }

    void evaluate(Transaction *t,
        RuleWithActions *rule,
        std::vector<const VariableValue *> *l) override {
        Rule_DictElement::id(t, rule, l);
        Rule_DictElement::rev(t, rule, l);
        Rule_DictElement::severity(t, rule, l);
        Rule_DictElement::logData(t, rule, l);
        Rule_DictElement::msg(t, rule, l);
    }
};

// DEFINE_VARIABLE_DICT(Rule, RULE, m_variableRule)


}  // namespace variables
}  // namespace modsecurity

#endif  // SRC_VARIABLES_RULE_H_
