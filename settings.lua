require("commons")

data:extend({
    {
        name = own"delay",
        type = "int-setting",
        setting_type = "runtime-per-user",
        minimum_value = 0,
        maximum_value = 30,
        default_value = 2,
        order = "0",
    },
    {
        name = own"hide-minimap",
        type = "bool-setting",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "1",
    },
    {
        name = own"show-minimap-while-driving",
        type = "bool-setting",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "1.1",
    },
    {
        name = own"hide-quickbar",
        type = "bool-setting",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "2",
    },
    {
        name = own"show-quickbar-in-combat",
        type = "bool-setting",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "2.1",
    },
    {
        name = own"hide-top",
        type = "bool-setting",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "3.1",
    },
    {
        name = own"hide-left",
        type = "bool-setting",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "3.2",
    },
    {
        name = own"hide-goal",
        type = "bool-setting",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "3.3",
    },
})
