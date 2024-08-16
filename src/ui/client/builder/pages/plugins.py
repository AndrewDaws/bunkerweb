from .utils.widgets import (
    button_widget,
    button_group_widget,
    title_widget,
    subtitle_widget,
    text_widget,
    tabulator_widget,
    input_widget,
    icons_widget,
    regular_widget,
    unmatch_widget,
)
from .utils.table import add_column
from .utils.format import get_fields_from_field
from typing import Optional

columns = [
    add_column(title="Name", field="name", formatter="text"),
    add_column(title="Version", field="version", formatter="text"),
    add_column(title="Description", field="description", formatter="text", maxWidth=400),
    add_column(title="Type", field="type", formatter="text"),
    add_column(title="Actions", field="actions", formatter="buttongroup"),
]


def plugins_filter(types: Optional[list] = None) -> list:
    filters = [
        {
            "type": "like",
            "fields": ["name"],
            "setting": {
                "id": "input-search-name",
                "name": "input-search-name",
                "label": "plugins_search",  # keep it (a18n)
                "placeholder": "inp_keyword",  # keep it (a18n)
                "value": "",
                "inpType": "input",
                "columns": {"pc": 3, "tablet": 4, "mobile": 12},
                "popovers": [
                    {
                        "iconName": "info",
                        "text": "plugins_search_desc",
                    }
                ],
                "fieldSize": "sm",
            },
        }
    ]

    if types is not None and (isinstance(types, list) and len(types) >= 2):
        filters.append(
            {
                "type": "=",
                "fields": ["type"],
                "setting": {
                    "id": "select-type",
                    "name": "select-type",
                    "label": "plugins_type",  # keep it (a18n)
                    "value": "all",  # keep "all"
                    "values": ["all"] + types,
                    "inpType": "select",
                    "onlyDown": True,
                    "columns": {"pc": 3, "tablet": 4, "mobile": 12},
                    "popovers": [
                        {
                            "iconName": "info",
                            "text": "plugins_type_desc",
                        }
                    ],
                    "fieldSize": "sm",
                },
            }
        )

    return filters


def plugin_item(
    name: str,
    version: str,
    description: str,
    is_deletable: bool,
    page: str,
    plugin_type: str,
):

    # Actions
    actions = []

    if page:
        actions.append(
            button_widget(
                id=f"plugin-page-{name}",
                text="action_redirect",  # keep it (a18n)
                color="info",
                size="normal",
                hideText=True,
                iconName="redirect",
                iconColor="white",
                attrs={"data-link": f"plugins/{name}"},
            ),
        )

    if is_deletable:
        actions.append(
            button_widget(
                id=f"plugin-delete-{name}",
                text="action_delete",  # keep it (a18n)
                color="error",
                size="normal",
                hideText=True,
                iconName="trash",
                iconColor="white",
                modal={
                    "widgets": [
                        title_widget(title="plugins_delete_title"),  # keep it (a18n)
                        text_widget(text="plugins_delete_subtitle"),  # keep it (a18n)
                        text_widget(bold=True, text=name),
                        button_group_widget(
                            buttons=[
                                button_widget(
                                    id=f"close-delete-btn-{name}",
                                    text="action_close",  # keep it (a18n)
                                    color="close",
                                    size="normal",
                                    attrs={"data-close-modal": ""},  # a11y
                                ),
                                button_widget(
                                    id=f"delete-btn-{name}",
                                    text="action_delete",  # keep it (a18n)
                                    color="delete",
                                    size="normal",
                                    iconName="trash",
                                    iconColor="white",
                                    attrs={
                                        "data-submit-form": f"""{{ "plugin" : "{name}", "type": "{plugin_type}" }}""",
                                        "data-submit-endpoint": "/delete",
                                        "data-submit-method": "DELETE",
                                    },
                                ),
                            ]
                        ),
                    ],
                },
            ),
        )

    return {
        "name": text_widget(text=name)["data"],
        "type": text_widget(text=plugin_type)["data"],
        "version": text_widget(text=version)["data"],
        "description": text_widget(text=description)["data"],
        "actions": {"buttons": actions},
    }


def fallback_message(msg: str, display: Optional[list] = None) -> dict:

    return {
        "type": "void",
        "display": display if display else [],
        "widgets": [
            unmatch_widget(text=msg),
        ],
    }


def plugins_list(plugins: Optional[list] = None, types: Optional[list] = None) -> dict:

    if plugins is None or (isinstance(plugins, list) and len(plugins) == 0):
        return fallback_message(msg="plugins_not_found")

    items = []

    for plugin in plugins:
        items.append(
            plugin_item(
                name=plugin["name"],
                version=plugin["version"],
                description=plugin["description"],
                is_deletable=plugin["is_deletable"],
                page=plugin["page"],
                plugin_type=plugin["type"],
            )
        )

    return {
        "type": "card",
        "widgets": [
            title_widget(
                title="plugins_list_title",  # keep it (a18n)
            ),
            subtitle_widget(
                subtitle="plugins_list_subtitle",  # keep it (a18n)
            ),
            tabulator_widget(
                id="table-plugins",
                layout="fitColumns",
                columns=columns,
                items=items,
                filters=plugins_filter(types=types),
            ),
        ],
    }


def plugins_builder(plugins: Optional[list] = None, types: Optional[list] = None) -> list:
    return [plugins_list(plugins=plugins, types=types)]
