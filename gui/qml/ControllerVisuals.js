.pragma library

// Visual-only metadata shared by the native details panel. Input state still
// belongs to the service; these lists never imply that a button was pressed.
var base = "../../ui/assets/";

function kind(family, name) {
    var n = (name || "").toLowerCase();
    if (family === "joycon") {
        if (n.indexOf("(l)") !== -1 || n.indexOf("joy-con l") !== -1) return "joyconl";
        if (n.indexOf("(r)") !== -1 || n.indexOf("joy-con r") !== -1) return "joyconr";
        return "unknown";
    }
    if (family === "joycon-combined") return "joyconpair";
    if (family === "switch-pro") return "pro";
    if (family === "ps3") return "dualshock";
    if (family === "dualshock4") return "ds4";
    if (family === "dualsense") return "dualsense";
    if (family === "xbox360") return "xbox360";
    if (family === "xbox-bluetooth") return "xboxone";
    if (family === "xbox-one-series") return n.indexOf("series") !== -1 ? "xboxseries" : "xboxone";
    return "unknown";
}

function artwork(type) {
    var refs = {
        pro: "steam/switch-pro.png",
        dualshock: "dualshock-3-transparent-white.png",
        ds4: "steam/dualshock-4.png",
        dualsense: "steam/dualsense.png",
        xbox360: "xbox-360-xcf-ui.svg",
        xboxone: "steam/xbox-one.png",
        xboxseries: "xbox-series-front.svg",
        joyconl: "steam/joycon-l.png",
        joyconr: "steam/joycon-r.png",
        joyconpair: "steam/joycon-pair.png"
    };
    return refs[type] ? base + "controller-references/" + refs[type] : "";
}

function button(label, icon, color) {
    return { label: label, icon: icon || "", color: color || "" };
}

function faceOverlays(type) {
    var n = {A: "#e23441", B: "#edb929", X: "#2879df", Y: "#1dae72"};
    var x = {A: "#53b92c", B: "#d93635", X: "#2879df", Y: "#e8bf1f"};
    var positions = {
        pro: [["X",76.3,20.23],["Y",68.6,30.06],["A",84.1,30.06],["B",76.3,39.03]],
        xboxone: [["Y",76.2,18.3],["X",69,27.7],["B",82.9,27.7],["A",76.2,37.4]],
        xboxseries: [["Y",76.2,27],["X",69,36.4],["B",82.9,36.4],["A",76.2,45.9]],
        joyconr: [["Y",73.5,46.5],["X",80.8,63.3],["B",66.4,63.3],["A",73.5,79.5]],
        joyconpair: [["X",83.3,19.3],["Y",75.8,26.6],["A",90.5,26.6],["B",83.3,33.7]],
        ds4: [["Triangle",81.3,18.06],["Square",74,30.32],["Circle",88.6,30.32],["Cross",81.3,42.26]],
        dualsense: [["Triangle",81.7,16.52],["Square",75.1,26.70],["Circle",88.5,26.70],["Cross",81.7,36.58]]
    };
    return (positions[type] || []).map(function (p) {
        var playstation = type === "ds4" || type === "dualsense";
        return {label:p[0], x:p[1], y:p[2], color:(type.indexOf("xbox") === 0 ? x : n)[p[0]] || "",
                icon:playstation ? "ps_wire_button_" + p[0].toLowerCase() : ""};
    });
}

function groups(type) {
    var ps = [button("Triangle", "ps_wire_button_triangle"), button("Circle", "ps_wire_button_circle"),
              button("Cross", "ps_wire_button_x"), button("Square", "ps_wire_button_square")];
    var xbox = [button("A", "shared_color_button_a"), button("B", "shared_color_button_b"),
                button("X", "shared_color_button_x"), button("Y", "shared_color_button_y")];
    var nintendo = [button("A", "", "#e23441"), button("B", "", "#edb929"),
                    button("X", "", "#2879df"), button("Y", "", "#1dae72")];
    var psDpad = ["up", "down", "left", "right"].map(function (d) { return button(d, "ps_dpad_" + d); });
    var nDpad = ["up", "down", "left", "right"].map(function (d) { return button(d, "switchpro_dpad_" + d); });
    var xDpad = ["up", "down", "left", "right"].map(function (d) { return button(d, "shared_dpad_" + d); });
    var face = [], dpad = [], shoulders = [], system = [];
    if (type === "pro" || type === "joyconr" || type === "joyconpair") face = nintendo;
    else if (["dualshock", "ds4", "dualsense"].indexOf(type) !== -1) face = ps;
    else if (["xbox360", "xboxone", "xboxseries"].indexOf(type) !== -1) face = xbox;
    if (["pro", "joyconl", "joyconpair"].indexOf(type) !== -1) dpad = nDpad;
    else if (["dualshock", "ds4", "dualsense"].indexOf(type) !== -1) dpad = psDpad;
    else if (["xbox360", "xboxone", "xboxseries"].indexOf(type) !== -1) dpad = xDpad;

    if (type === "pro" || type === "joyconpair") {
        shoulders = [button("L", "switchpro_l"), button("ZL", "switchpro_l2"),
                     button("R", "switchpro_r"), button("ZR", "switchpro_r2")];
        system = [button("L pressed", "switchpro_lstick_click"), button("R pressed", "switchpro_rstick_click"),
                  button("Minus", "switchpro_button_minus"), button("Plus", "switchpro_button_plus"),
                  button("Capture", "switchpro_button_capture"), button("Home", "switchpro_button_home")];
    } else if (type === "joyconl" || type === "joyconr") {
        var left = type === "joyconl";
        shoulders = [button(left ? "L" : "R", left ? "switchpro_l" : "switchpro_r"),
                     button(left ? "ZL" : "ZR", left ? "switchpro_l2" : "switchpro_r2"),
                     button("SL", left ? "joycon_left_sl" : "joycon_right_sl"),
                     button("SR", left ? "joycon_left_sr" : "joycon_right_sr")];
        system = [button(left ? "L pressed" : "R pressed", left ? "switchpro_lstick_click" : "switchpro_rstick_click"),
                  button(left ? "Minus" : "Plus", left ? "switchpro_button_minus" : "switchpro_button_plus"),
                  button(left ? "Capture" : "Home", left ? "switchpro_button_capture" : "switchpro_button_home")];
    } else if (["dualshock", "ds4", "dualsense"].indexOf(type) !== -1) {
        var five = type === "dualsense";
        shoulders = [button("L1", five ? "ps5_l1" : "ps4_l1"), button("L2", five ? "ps5_l2" : "ps4_l2"),
                     button("R1", five ? "ps5_r1" : "ps4_r1"), button("R2", five ? "ps5_r2" : "ps4_r2")];
        system = [button("L3", "shared_l3"), button("R3", "shared_r3")];
        if (type === "dualshock") system = system.concat([button("Select", "ps3_select"), button("Start", "ps3_start")]);
        else system = system.concat([button("Touchpad", "ps5_trackpad_click"),
            button(five ? "Create" : "Share", five ? "ps5_button_create" : "ps4_button_share"),
            button("Options", five ? "ps5_button_options" : "ps4_button_options")]);
        system.push(button("PS", "ps4_button_logo"));
        if (five) system.push(button("Mute", "ps_button_mute"));
    } else if (["xbox360", "xboxone", "xboxseries"].indexOf(type) !== -1) {
        shoulders = [button("LB", "xbox_lb"), button("LT", "xbox_lt"), button("RB", "xbox_rb"), button("RT", "xbox_rt")];
        system = [button("LS", "xbox_ls_click"), button("RS", "xbox_rs_click"),
                  button(type === "xbox360" ? "Back" : "View", type === "xbox360" ? "xbox360_button_select" : "xbox_button_select"),
                  button(type === "xbox360" ? "Start" : "Menu", type === "xbox360" ? "xbox360_button_start" : "xbox_button_start")];
        if (type === "xboxseries") system.push(button("Share", "xbox_button_share"));
        system.push(button("Xbox", "xbox_button_logo"));
    }
    return [{title: "Face buttons", buttons: face}, {title: "D-pad", buttons: dpad},
            {title: "Shoulders and triggers", buttons: shoulders}, {title: "System and auxiliary", buttons: system}]
        .filter(function (group) { return group.buttons.length > 0; });
}
