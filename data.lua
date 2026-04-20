require("commons")

data:extend({
    {
        type = "custom-input",
        name = own"activate",
        key_sequence = "ALT + H",
    },

    {
        type = "custom-input",
        name = own"increase-ui-scale",
        linked_game_control = "increase-ui-scale",
        key_sequence = "",
    },
    {
        type = "custom-input",
        name = own"decrease-ui-scale",
        linked_game_control = "decrease-ui-scale",
        key_sequence = "",
    },
    {
        type = "custom-input",
        name = own"reset-ui-scale",
        linked_game_control = "reset-ui-scale",
        key_sequence = "",
    },

    {
        type = "custom-input",
        name = own"next-weapon",
        linked_game_control = "next-weapon",
        key_sequence = "",
    },
    {
        type = "custom-input",
        name = own"shoot-enemy",
        linked_game_control = "shoot-enemy",
        key_sequence = "",
    },
    {
        type = "custom-input",
        name = own"shoot-selected",
        linked_game_control = "shoot-selected",
        key_sequence = "",
    },

    {
        type = "custom-input",
        name = own"rotate-active-quick-bars",
        linked_game_control = "rotate-active-quick-bars",
        key_sequence = "",
    },
    {
        type = "custom-input",
        name = own"next-active-quick-bar",
        linked_game_control = "next-active-quick-bar",
        key_sequence = "",
    },
    {
        type = "custom-input",
        name = own"previous-active-quick-bar",
        linked_game_control = "previous-active-quick-bar",
        key_sequence = "",
    },
})

for i = 1, 10 do
    data:extend({
        {
            type = "custom-input",
            name = own("action-bar-select-page-"..i),
            linked_game_control = "action-bar-select-page-"..i,
            key_sequence = "",
        },
    })
end

-- Workaround (Factorio v2.0.76) for non-functioning quickbar hotkeys
for i = 1, 10 do
    data:extend({
        {
            type = "custom-input",
            name = own("quick-bar-button-"..i),
            linked_game_control = "quick-bar-button-"..i,
            key_sequence = "",
        },
        {
            type = "custom-input",
            name = own("quick-bar-button-"..i.."-secondary"),
            linked_game_control = "quick-bar-button-"..i.."-secondary",
            key_sequence = "",
        }
    })
end
