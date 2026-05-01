import Foundation

/// Destinations for the root NavigationStack.
enum NavigationDestination: Hashable {
    case settings
    case projectCreate
    case projectEdit(Project)
    case milestoneEdit(project: Project, milestone: Milestone?)
    case report
    case acknowledgments
    case licenseText
    case dataMaintenance
}
