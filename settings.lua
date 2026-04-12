require("commons")

data:extend({
    {
        name = own"delay",
        type = "int-setting",
        setting_type = "runtime-per-user",
        minimum_value = 1,
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
        name = own"hide-quickbar",
        type = "bool-setting",
        setting_type = "runtime-per-user",
        default_value = true,
        order = "1",
    },
})
