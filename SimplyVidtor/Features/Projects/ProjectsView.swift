import SwiftUI

struct ProjectsView: View {
    let projects: [ProjectSummary]
    let onNewProject: () -> Void
    let onOpen: (ProjectSummary) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.sm)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("Projects")
                    .font(Theme.Typography.display)
                    .accessibilityAddTraits(.isHeader)

                newProjectCard

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Recent")
                        .font(Theme.Typography.headline)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                        ForEach(projects) { project in
                            ProjectCard(project: project) { onOpen(project) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.vertical, Theme.Spacing.md)
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .background(Theme.Palette.bgBase)
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
}

private struct ProjectCard: View {
    let project: ProjectSummary
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
                        Text(Duration.seconds(project.duration), format: .time(pattern: .minuteSecond))
                            .font(Theme.Typography.timecode)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(Theme.Palette.scrim, in: .capsule)
                            .padding(Theme.Spacing.xs)
                    }
                Text(project.name)
                    .font(Theme.Typography.callout.weight(.semibold))
                    .lineLimit(1)
                Text(project.modified, format: .relative(presentation: .named))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ProjectsView(projects: ProjectSummary.samples, onNewProject: {}, onOpen: { _ in })
        .preferredColorScheme(.dark)
}
