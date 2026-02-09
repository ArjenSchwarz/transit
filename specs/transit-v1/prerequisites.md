# Prerequisites for Transit V1

These tasks must be completed by the user before or during implementation.

## Before Starting

- [ ] Create a new Xcode project with a multiplatform SwiftUI app target (iOS/iPadOS/macOS) named "Transit"
  - Set deployment targets to iOS 26, iPadOS 26, macOS 26
  - Use SwiftUI app lifecycle (`@main` struct)
  - Bundle identifier: choose your reverse-domain identifier (e.g., `com.example.transit`)
  - Set the product name to "Transit"

- [ ] Enable iCloud capability in the Xcode project
  - Add the "iCloud" capability to the target
  - Check "CloudKit" under iCloud Services
  - Create or select an iCloud container (e.g., `iCloud.com.example.transit`)

- [ ] Enable Background Modes capability (for CloudKit push notifications)
  - Add "Background Modes" capability
  - Check "Remote notifications"

## During Implementation

- [ ] Before task 13 (DisplayIDAllocator): Verify the CloudKit container is accessible
  - Open CloudKit Dashboard and confirm the container exists
  - The `DisplayIDCounter` record type will be auto-created in the development environment on first write

## Before Testing

- [ ] Deploy CloudKit schema to production before shipping
  - In CloudKit Dashboard, promote the development schema (including `DisplayIDCounter` record type) to production
  - This is required for the display ID counter to work in production builds
