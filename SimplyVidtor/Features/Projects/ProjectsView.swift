import SwiftData
import SwiftUI

struct ProjectsView: View {
    let onNewProject: () -> Void
    let onOpen: (Project) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Project.modifiedAt, order: .reverse) private var projects: [Project]

    @State private var renaming: Project?
    @State private var newName = ""
    @State private var deleting: Project?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.sm)]
    private var library: ProjectLibrary { ProjectLibrary(context: context) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("Projects")
                    .font(Theme.Typography.display)
                    .accessibilityAddTraits(.isHeader)

                newProjectCard

                if projects.isEmpty {
                    Text("Your projects will appear here.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xl)
                } else {
                    recentGrid
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.vertical, Theme.Spacing.md)
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .background(Theme.Palette.bgBase)
        .alert("Rename Project", isPresented: isPresented($renaming)) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let renaming { try? library.rename(renaming, to: newName) }
            }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: isPresented($deleting),
            titleVisibility: .visible,
            presenting: deleting
        ) { project in
            Button("Delete Project", role: .destructive) { try? library.delete(project) }
        } message: { _ in
            Text("This can’t be undone.")
        }
    }

    private var newProjectCard: some View {
        Button(action: onNewProject) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "plus")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.onAccent)
                    .frame(width: Theme.Size.buttonHeight, height: Theme.Size.buttonHeight)
                    .background(Theme.Palette.accent, in: .circle)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("New Project")
                        .font(Theme.Typography.headline)
                    Text("Pick clips to start editing")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.bgSurface, in: .rect(cornerRadius: Theme.Radius.cardLarge))
            .contentShape(.rect(cornerRadius: Theme.Radius.cardLarge))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("projects.newProject")
    }

    private var recentGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recent")
                .font(Theme.Typography.headline)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                ForEach(projects) { project in
                    ProjectCard(project: project) { onOpen(project) }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                newName = project.name
                                renaming = project
                            }
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                _ = try? library.duplicate(project)
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                deleting = project
                            }
                        }
                }
            }
        }
    }

    private func isPresented(_ item: Binding<Project?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

private struct ProjectCard: View {
    let project: Project
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.Palette.bgSurfaceRaised)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .overlay {
                        Image(systemName: "film")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text(Duration.seconds(duration), format: .time(pattern: .minuteSecond))
                            .font(Theme.Typography.timecode)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(Theme.Palette.scrim, in: .capsule)
                            .padding(Theme.Spacing.xs)
                    }
                Text(project.name)
                    .font(Theme.Typography.callout.weight(.semibold))
                    .lineLimit(1)
                Text(project.modifiedAt, format: .relative(presentation: .named))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("projects.card.\(project.name)")
    }

    private var duration: Double {
        (try? project.loadTimeline().duration) ?? 0
    }
}

#Preview("Projects") {
    ProjectsView(onNewProject: {}, onOpen: { _ in })
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    ProjectsView(onNewProject: {}, onOpen: { _ in })
        .modelContainer(PreviewData.container(withSamples: false))
        .preferredColorScheme(.dark)
}
