import SwiftUI

/// Export settings, then progress, then the result. Settings are remembered.
struct ExportSheet: View {
    let session: EditorSession
    let store: MediaStore
    let onClose: () -> Void

    private enum Phase: Equatable {
        case settings
        case exporting(progress: Double)
        case done(URL)
        case failed(String)
    }

    @State private var phase = Phase.settings
    @State private var exportTask: Task<Void, Never>?
    @AppStorage("export.resolution") private var resolution = ExportSettings.Resolution.p1080.rawValue
    @AppStorage("export.frameRate") private var frameRate = 30
    @AppStorage("export.hevc") private var usesHEVC = false

    private var settings: ExportSettings {
        ExportSettings(
            resolution: ExportSettings.Resolution(rawValue: resolution) ?? .p1080,
            frameRate: ExportSettings.frameRates.contains(frameRate) ? frameRate : 30,
            usesHEVC: usesHEVC
        )
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack {
                Text(title)
                    .font(Theme.Typography.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !isExporting {
                    CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close", action: close)
                        .accessibilityIdentifier("export.close")
                }
            }

            switch phase {
            case .settings: settingsForm
            case .exporting(let progress): exportingView(progress)
            case .done(let url): doneView(url)
            case .failed(let message): failedView(message)
            }
        }
        .padding(Theme.Spacing.gutter)
        .foregroundStyle(Theme.Palette.textPrimary)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Palette.bgSurface)
        .presentationCornerRadius(Theme.Radius.sheet)
        .presentationDragIndicator(isExporting ? .hidden : .visible)
        .interactiveDismissDisabled(isExporting)
        .onDisappear(perform: cleanUp)
    }

    private var isExporting: Bool {
        if case .exporting = phase { true } else { false }
    }

    private var title: LocalizedStringKey {
        switch phase {
        case .settings: "Export"
        case .exporting: "Exporting"
        case .done: "Exported"
        case .failed: "Export Failed"
        }
    }

    // MARK: - Settings

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            labeled("Resolution") {
                SegmentedPicker(selection: $resolution, options: ExportSettings.Resolution.allCases.map(\.rawValue)) {
                    Text(ExportSettings.Resolution(rawValue: $0)?.title ?? "")
                }
                .accessibilityIdentifier("export.resolution")
            }
            labeled("Frame Rate") {
                SegmentedPicker(selection: $frameRate, options: ExportSettings.frameRates) { Text("\($0) fps") }
                    .accessibilityIdentifier("export.frameRate")
            }
            Toggle(isOn: $usesHEVC) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("HEVC")
                    Text("Smaller files; plays on recent devices")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .toggleStyle(.accentSwitch)
            .accessibilityIdentifier("export.hevc")

            let size = settings.renderSize(for: session.renderSize)
            HStack {
                Text("\(Int(size.width)) × \(Int(size.height))")
                Spacer()
                Text("About \(ByteCountFormatter.string(fromByteCount: settings.estimatedBytes(duration: session.duration, canvas: session.renderSize), countStyle: .file))")
                    .accessibilityIdentifier("export.estimate")
            }
            .font(Theme.Typography.callout)
            .foregroundStyle(Theme.Palette.textSecondary)

            Spacer(minLength: 0)
            Button("Export Video", action: startExport)
                .buttonStyle(.primary)
                .disabled(session.timeline.clips.isEmpty)
                .accessibilityIdentifier("export.start")
        }
    }

    private func labeled(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
            content()
        }
    }

    // MARK: - Phases

    private func exportingView(_ progress: Double) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(Theme.Palette.separator, lineWidth: Theme.Size.sliderTrack * 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.Palette.accent, style: StrokeStyle(lineWidth: Theme.Size.sliderTrack * 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: progress)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(Theme.Typography.title.monospacedDigit())
                    .accessibilityIdentifier("export.progress")
            }
            .frame(width: Theme.Size.buttonHeight * 2.5, height: Theme.Size.buttonHeight * 2.5)
            Text("Keep the app open until the export finishes.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: 0)
            Button("Cancel", role: .cancel) { exportTask?.cancel() }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("export.cancel")
        }
    }

    private func doneView(_ url: URL) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Theme.Size.buttonHeight))
                .foregroundStyle(Theme.Palette.accent)
            Text("Your video is ready.")
                .font(Theme.Typography.headline)
                .accessibilityIdentifier("export.done")
            Spacer(minLength: 0)
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("export.share")
            Button("Done", action: close)
                .buttonStyle(.secondary)
                .accessibilityIdentifier("export.finish")
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            ContentUnavailableView("Export Failed", systemImage: "exclamationmark.triangle", description: Text(message))
            Spacer(minLength: 0)
            Button("Try Again") { phase = .settings }
                .buttonStyle(.primary)
                .accessibilityIdentifier("export.retry")
        }
    }

    // MARK: - Actions

    private func startExport() {
        session.pause()
        phase = .exporting(progress: 0)
        let timeline = session.timeline
        let settings = settings
        exportTask = Task {
            do {
                let url = try await Exporter.export(timeline, store: store, settings: settings) { progress in
                    Task { @MainActor in
                        if case .exporting = phase { phase = .exporting(progress: progress) }
                    }
                }
                phase = .done(url)
            } catch is CancellationError {
                phase = .settings
            } catch {
                phase = Task.isCancelled ? .settings : .failed(error.localizedDescription)
            }
        }
    }

    private func close() {
        cleanUp()
        onClose()
    }

    /// Stops a running export and deletes the exported file.
    private func cleanUp() {
        exportTask?.cancel()
        if case .done(let url) = phase { try? FileManager.default.removeItem(at: url) }
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    return Color.clear.sheet(isPresented: .constant(true)) {
        ExportSheet(session: session, store: .temporary(), onClose: {})
    }
    .preferredColorScheme(.dark)
}
