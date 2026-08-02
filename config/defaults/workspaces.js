.pragma library

var data = {
    "shown": 10,
    // Per-monitor workspace stride for hyprsome / decade-prefix layouts
    // (e.g. mon0: 1-10, mon1: 11-20). Default 10 matches those layouts even
    // when fewer slots are shown. Set to 0 to use the same value as `shown`
    // (legacy: group stride == button count).
    "groupSize": 10,
    "showAppIcons": true,
    "alwaysShowNumbers": false,
    "showNumbers": false,
    "dynamic": false
}
