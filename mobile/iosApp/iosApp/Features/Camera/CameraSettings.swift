import Foundation

/// The camera settings FEAT-012 keeps across a relaunch: the eight user-facing controls of the
/// camera screen and the placement of the pose reference. The selected pose is deliberately **not**
/// here (decision D8) — `CameraSnapshot.pose_json` stays untouched by this type.
///
/// The type is the JSON contract of `CameraSnapshot.settings_json` (`settings only, no schema
/// migration`), so decoding is defensive in three ways:
/// - every field is optional (`decodeIfPresent`), so a partial object fills the rest with defaults;
/// - every numeric field is clamped or replaced when it is not finite, so a hand-edited or corrupt
///   value cannot put the UI in an impossible state;
/// - an unknown enum value falls back to the default instead of throwing, so one bad field never
///   costs the user the other seven.
struct CameraSettings: Equatable, Sendable {
    /// Bumped when the JSON shape changes in a way that needs a reader.
    static let currentVersion = 1
    static let guideOpacityRange: ClosedRange<Double> = 0...1

    var version = 1
    /// Monotonic write counter carried inside the JSON. `CameraSnapshotRepository.saveSettings`
    /// only stores a payload that is newer than the stored one, so a debounced write that lands
    /// after a newer one can never roll the row back.
    var revision: Int64 = 0
    var guideOpacity = 0.5
    /// C3-Q2: no control exists for it yet, so it stays `false`, but it is persisted as D8 says.
    var guideFlipped = false
    var isGridVisible = false
    var flash: CameraFlashSetting = .auto
    var isPoseGuideVisible = true
    var lineColor: GuideLineColor = .pink
    var transform = Transform()
    var zoom: CameraZoomLevel = .one
    /// The exact zoom the lens was at. `zoom` keeps every pre-existing row readable; the factor adds
    /// the lenses' 0.5x stop, which the level enum cannot express.
    var zoomFactor: Double = 1
    /// Retired with the inline pose picker strip: the picker is a sheet now, so nothing reads this. It
    /// stays in the codec because the field is part of the stored JSON contract — a row written while
    /// the strip existed must still decode (and must not cost the user the settings that still matter).
    var isPickerExpanded = true
    /// Shutter timer (Off / 3 s / 10 s). Default off: a press captures at once.
    var timer: CameraTimerSetting = .off
    /// Saved capture aspect. Default 3:4: the camera's portrait framing.
    var aspectRatio: CameraAspectRatio = .threeFour

    /// The restored placement in the shape the camera screen draws.
    var guideTransform: GuideTransform { transform.placement }

    init() {}

    init(
        version: Int = CameraSettings.currentVersion,
        revision: Int64 = 0,
        guideOpacity: Double = 0.5,
        guideFlipped: Bool = false,
        isGridVisible: Bool = false,
        flash: CameraFlashSetting = .auto,
        isPoseGuideVisible: Bool = true,
        lineColor: GuideLineColor = .pink,
        transform: Transform = Transform(),
        zoom: CameraZoomLevel = .one,
        zoomFactor: Double? = nil,
        isPickerExpanded: Bool = true,
        timer: CameraTimerSetting = .off,
        aspectRatio: CameraAspectRatio = .threeFour
    ) {
        self.version = version
        self.revision = revision
        self.guideOpacity = guideOpacity
        self.guideFlipped = guideFlipped
        self.isGridVisible = isGridVisible
        self.flash = flash
        self.isPoseGuideVisible = isPoseGuideVisible
        self.lineColor = lineColor
        self.transform = transform
        self.zoom = zoom
        // A caller that sets only the level (every pre-existing call site) keeps the factor in step:
        // the factor exists to add the lenses' 0.5x stop, not to create a second source of truth.
        self.zoomFactor = CameraSettings.finiteZoom(zoomFactor ?? Double(zoom.rawValue))
        self.isPickerExpanded = isPickerExpanded
        self.timer = timer
        self.aspectRatio = aspectRatio
    }

    /// Placement of the pose reference over the preview, in a JSON-friendly (finite, clamped) shape.
    struct Transform: Equatable, Sendable {
        /// Same range as `GuideTransform.scaleRange`, in the JSON type.
        static let scaleRange: ClosedRange<Double> =
            Double(GuideTransform.scaleRange.lowerBound)...Double(GuideTransform.scaleRange.upperBound)

        var scale = 1.0
        var rotationDegrees = 0.0
        var offsetX = 0.0
        var offsetY = 0.0

        init(scale: Double = 1, rotationDegrees: Double = 0, offsetX: Double = 0, offsetY: Double = 0) {
            self.scale = Self.clampedScale(scale)
            self.rotationDegrees = Self.finite(rotationDegrees)
            self.offsetX = Self.finite(offsetX)
            self.offsetY = Self.finite(offsetY)
        }

        init(_ placement: GuideTransform) {
            self.init(
                scale: Double(placement.scale),
                rotationDegrees: placement.rotation.degrees,
                offsetX: Double(placement.offset.width),
                offsetY: Double(placement.offset.height)
            )
        }

        var placement: GuideTransform {
            GuideTransform(
                scale: CGFloat(scale),
                rotation: .degrees(rotationDegrees),
                offset: CGSize(width: offsetX, height: offsetY)
            )
        }

        static func clampedScale(_ value: Double) -> Double {
            guard value.isFinite else { return 1 }
            return min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
        }

        static func finite(_ value: Double) -> Double {
            value.isFinite ? value : 0
        }
    }
}

// MARK: - Codec

extension CameraSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case version, revision, guideOpacity, guideFlipped, isGridVisible, flash,
             isPoseGuideVisible, lineColor, transform, zoom, zoomFactor, isPickerExpanded, timer, aspectRatio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CameraSettings()

        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? defaults.version
        revision = (try? container.decodeIfPresent(Int64.self, forKey: .revision)) ?? defaults.revision
        guideOpacity = Self.clampedOpacity(
            (try? container.decodeIfPresent(Double.self, forKey: .guideOpacity)) ?? nil
        )
        guideFlipped = (try? container.decodeIfPresent(Bool.self, forKey: .guideFlipped)) ?? defaults.guideFlipped
        isGridVisible = (try? container.decodeIfPresent(Bool.self, forKey: .isGridVisible)) ?? defaults.isGridVisible
        flash = Self.flash(from: (try? container.decodeIfPresent(String.self, forKey: .flash)) ?? nil)
        isPoseGuideVisible =
            (try? container.decodeIfPresent(Bool.self, forKey: .isPoseGuideVisible)) ?? defaults.isPoseGuideVisible
        // A row from before the palette says `white`; `GuideLineColor.stored` maps it to the sheet's default.
        lineColor = GuideLineColor.stored((try? container.decodeIfPresent(String.self, forKey: .lineColor)) ?? nil)
            ?? defaults.lineColor
        transform = ((try? container.decodeIfPresent(Transform.self, forKey: .transform)) ?? nil)
            ?? defaults.transform
        zoom = ((try? container.decodeIfPresent(Int.self, forKey: .zoom)) ?? nil)
            .flatMap(CameraZoomLevel.init(rawValue:)) ?? defaults.zoom
        zoomFactor = CameraSettings.finiteZoom(
            (try? container.decodeIfPresent(Double.self, forKey: .zoomFactor)) ?? nil ?? Double(defaults.zoom.factor)
        )
        isPickerExpanded = (try? container.decodeIfPresent(Bool.self, forKey: .isPickerExpanded)) ?? defaults.isPickerExpanded
        timer = ((try? container.decodeIfPresent(String.self, forKey: .timer)) ?? nil)
            .flatMap(CameraTimerSetting.init(rawValue:)) ?? defaults.timer
        aspectRatio = ((try? container.decodeIfPresent(String.self, forKey: .aspectRatio)) ?? nil)
            .flatMap(CameraAspectRatio.init(rawValue:)) ?? defaults.aspectRatio
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(revision, forKey: .revision)
        try container.encode(guideOpacity, forKey: .guideOpacity)
        try container.encode(guideFlipped, forKey: .guideFlipped)
        try container.encode(isGridVisible, forKey: .isGridVisible)
        try container.encode(flashRawValue, forKey: .flash)
        try container.encode(isPoseGuideVisible, forKey: .isPoseGuideVisible)
        try container.encode(lineColor.rawValue, forKey: .lineColor)
        try container.encode(transform, forKey: .transform)
        try container.encode(zoom.rawValue, forKey: .zoom)
        try container.encode(zoomFactor, forKey: .zoomFactor)
        try container.encode(isPickerExpanded, forKey: .isPickerExpanded)
        try container.encode(timer.rawValue, forKey: .timer)
        try container.encode(aspectRatio.rawValue, forKey: .aspectRatio)
    }

    /// `nil` when the payload is not a JSON object this type understands. Callers fall back to full
    /// defaults; a corrupt row must never crash or block the camera screen.
    static func decode(_ json: String) -> CameraSettings? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CameraSettings.self, from: data)
    }

    /// Sorted keys keep the stored bytes stable, which is what lets a repository test assert that a
    /// settings write leaves `pose_json` byte-identical.
    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    /// A zoom factor is always a positive, finite number: a corrupt row falls back to 1x.
    static func finiteZoom(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        return value
    }

    private static func clampedOpacity(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0.5 }
        return min(max(value, guideOpacityRange.lowerBound), guideOpacityRange.upperBound)
    }

    private static func flash(from raw: String?) -> CameraFlashSetting {
        switch raw {
        case "off": return .off
        case "on": return .on
        default: return .auto
        }
    }

    /// `CameraFlashSetting` is not `RawRepresentable` (the capture path owns its own ordering), so
    /// the JSON spelling lives here instead of widening that type.
    private var flashRawValue: String {
        switch flash {
        case .off: return "off"
        case .on: return "on"
        case .auto: return "auto"
        }
    }
}

extension CameraSettings.Transform: Codable {
    enum CodingKeys: String, CodingKey {
        case scale, rotationDegrees, offsetX, offsetY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scale: (try? container.decodeIfPresent(Double.self, forKey: .scale)) ?? nil ?? 1,
            rotationDegrees: (try? container.decodeIfPresent(Double.self, forKey: .rotationDegrees)) ?? nil ?? 0,
            offsetX: (try? container.decodeIfPresent(Double.self, forKey: .offsetX)) ?? nil ?? 0,
            offsetY: (try? container.decodeIfPresent(Double.self, forKey: .offsetY)) ?? nil ?? 0
        )
    }
}

// MARK: - Store

/// Reads and writes the persisted settings. Async because the database is opened and written off
/// the main thread; throwing because a broken row must degrade to defaults, not crash the camera.
protocol CameraSettingsStore: Sendable {
    func load() async throws -> CameraSettings?
    func save(_ settings: CameraSettings) async throws
}

/// GRDB implementation over the singleton `CameraSnapshot` row. The settings write is a
/// read-modify-write in **one** `database.write` transaction, so:
/// - `pose_json` is carried over from the row that was read (D8: a settings save never clears a
///   pose), and
/// - a payload whose `revision` is not newer than the stored one is dropped, so a debounced write
///   that arrives late cannot replace a newer one.
struct GRDBCameraSettingsStore: CameraSettingsStore {
    let database: AppDatabase

    func load() async throws -> CameraSettings? {
        guard let record = try await CameraSnapshotRepository(database: database).snapshot() else {
            return nil
        }
        return CameraSettings.decode(record.settingsJSON)
    }

    func save(_ settings: CameraSettings) async throws {
        let json = try settings.encodedJSON()
        try await CameraSnapshotRepository(database: database).saveSettings(
            CameraSnapshotSettingsWrite(
                json: json,
                schemaVersion: Int64(CameraSettings.currentVersion),
                revision: settings.revision,
                storedRevision: { CameraSettings.decode($0)?.revision ?? .min }
            )
        )
    }
}

/// In-memory fallback: used by tests, and when the database cannot be opened (a corrupt or
/// unreadable container must not take the camera settings with it).
actor InMemoryCameraSettingsStore: CameraSettingsStore {
    private var stored: CameraSettings?
    private(set) var saved: [CameraSettings] = []

    init(seed: CameraSettings? = nil) {
        stored = seed
    }

    func load() async throws -> CameraSettings? { stored }

    func save(_ settings: CameraSettings) async throws {
        saved.append(settings)
        stored = settings
    }
}

/// Opens the database the first time settings are actually needed, off the main thread, exactly
/// like `DeferredCapturePhotoMetadata` does for capture metadata. `CameraViewModel` is built on the
/// main thread while a tab switch is being resolved, so no database work may happen in its init.
actor DeferredCameraSettingsStore: CameraSettingsStore {
    private var resolved: (any CameraSettingsStore)?

    private func backend() -> any CameraSettingsStore {
        if let resolved { return resolved }
        let backend: any CameraSettingsStore
        if let database = try? AppDatabase() {
            backend = GRDBCameraSettingsStore(database: database)
        } else {
            backend = InMemoryCameraSettingsStore()
        }
        resolved = backend
        return backend
    }

    func load() async throws -> CameraSettings? {
        try await backend().load()
    }

    func save(_ settings: CameraSettings) async throws {
        try await backend().save(settings)
    }
}

/// The single funnel every settings write goes through. Actor methods only interleave at
/// suspension points and `write` has exactly one, so two writes cannot pass each other inside the
/// store; the revision guard would make the outcome correct even if they could.
actor CameraSettingsWriter {
    private let store: any CameraSettingsStore

    init(store: any CameraSettingsStore) {
        self.store = store
    }

    func write(_ settings: CameraSettings) async {
        // Persistence is best effort: a full disk or a broken row must not surface in the camera UI.
        try? await store.save(settings)
    }
}
