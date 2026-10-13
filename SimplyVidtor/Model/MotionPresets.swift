import Foundation

/// The animations that ship with the app, in the same format as imported packs.
nonisolated enum MotionPresets {
    private typealias K = MotionKeyframe

    static let fade = MotionAnimation(
        id: "builtin.fade", name: "Fade", roles: [.entrance, .exit],
        keyframes: [K(time: 0, opacity: 0, easing: .easeOut), K(time: 1)]
    )

    static let slide = MotionAnimation(
        id: "builtin.slide", name: "Slide", roles: [.entrance, .exit],
        keyframes: [K(time: 0, opacity: 0, offsetY: 0.2, easing: .snappy), K(time: 1)],
        isDirectional: true
    )

    static let pop = MotionAnimation(
        id: "builtin.pop", name: "Pop", roles: [.entrance, .exit],
        keyframes: [K(time: 0, opacity: 0, scale: 0, easing: .back), K(time: 1)]
    )

    static let bounce = MotionAnimation(
        id: "builtin.bounce", name: "Bounce", roles: [.entrance, .exit],
        keyframes: [
            K(time: 0, opacity: 0, offsetY: -0.3, easing: .easeIn),
            K(time: 0.5, offsetY: 0, easing: .easeOut),
            K(time: 0.7, offsetY: -0.06, easing: .easeIn),
            K(time: 0.85, offsetY: 0, easing: .easeOut),
            K(time: 0.93, offsetY: -0.015, easing: .easeIn),
            K(time: 1),
        ],
        defaultDuration: 0.9
    )

    static let spin = MotionAnimation(
        id: "builtin.spin", name: "Spin", roles: [.entrance, .exit],
        keyframes: [K(time: 0, opacity: 0, scale: 0, rotation: -.pi, easing: .snappy), K(time: 1)]
    )

    static let wipe = MotionAnimation(
        id: "builtin.wipe", name: "Wipe", roles: [.entrance, .exit],
        keyframes: [K(time: 0, reveal: 0, easing: .easeInOut), K(time: 1)],
        isDirectional: true
    )

    static let zoom = MotionAnimation(
        id: "builtin.zoom", name: "Zoom", roles: [.entrance, .exit],
        keyframes: [K(time: 0, opacity: 0, scale: 2.5, easing: .snappy), K(time: 1)]
    )

    static let pulse = MotionAnimation(
        id: "builtin.pulse", name: "Pulse", roles: [.loop],
        keyframes: [K(time: 0, easing: .easeInOut), K(time: 0.5, scale: 1.12, easing: .easeInOut), K(time: 1)]
    )

    static let float = MotionAnimation(
        id: "builtin.float", name: "Float", roles: [.loop],
        keyframes: [K(time: 0, easing: .easeInOut), K(time: 0.5, offsetY: -0.03, easing: .easeInOut), K(time: 1)],
        defaultDuration: 2
    )

    static let hop = MotionAnimation(
        id: "builtin.bounce-loop", name: "Bounce", roles: [.loop],
        keyframes: [K(time: 0, easing: .easeOut), K(time: 0.5, offsetY: -0.06, easing: .easeIn), K(time: 1)],
        defaultDuration: 0.8
    )

    static let wiggle = MotionAnimation(
        id: "builtin.wiggle", name: "Wiggle", roles: [.loop],
        keyframes: [
            K(time: 0, easing: .easeInOut), K(time: 0.25, rotation: 0.12, easing: .easeInOut),
            K(time: 0.75, rotation: -0.12, easing: .easeInOut), K(time: 1),
        ]
    )

    static let spinLoop = MotionAnimation(
        id: "builtin.spin-loop", name: "Spin", roles: [.loop],
        keyframes: [K(time: 0), K(time: 1, rotation: 2 * .pi)],
        hasStrength: false, defaultDuration: 2
    )

    static let typewriter = MotionAnimation(
        id: "builtin.typewriter", name: "Typewriter", roles: [.entrance, .exit],
        keyframes: [K(time: 0, opacity: 0), K(time: 1)],
        characterSpread: 1, defaultDuration: 1.2
    )

    static let cascade = MotionAnimation(
        id: "builtin.cascade", name: "Cascade", roles: [.entrance, .exit],
        keyframes: [K(time: 0, opacity: 0, offsetY: 0.08, easing: .snappy), K(time: 1)],
        isDirectional: true, characterSpread: 0.6, defaultDuration: 1
    )

    static let jump = MotionAnimation(
        id: "builtin.jump", name: "Jump", roles: [.entrance, .exit],
        keyframes: [K(time: 0, opacity: 0, scale: 0, easing: .back), K(time: 1)],
        characterSpread: 0.7, defaultDuration: 1
    )

    static let wave = MotionAnimation(
        id: "builtin.wave", name: "Wave", roles: [.loop],
        keyframes: [K(time: 0, easing: .easeOut), K(time: 0.5, offsetY: -0.04, easing: .easeIn), K(time: 1)],
        characterSpread: 0.5, defaultDuration: 1.5
    )

    static let all = [fade, slide, pop, bounce, spin, wipe, zoom, typewriter, cascade, jump,
                      pulse, float, hop, wiggle, spinLoop, wave]
}
