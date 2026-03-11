---
references:
    - specs/macos-settings-window/smolspec.md
---
# macOS Settings Window

## Settings Scene Setup

- [ ] 1. Settings scene added to TransitApp on macOS <!-- id:btw83r7 -->
  - TransitApp.swift has a Settings scene (macOS only) containing a NavigationStack with SettingsView as root.
  - The scene has navigationDestination handling all NavigationDestination cases exhaustively.
  - All environment objects, preferredColorScheme, and modelContainer are attached to the scene.
  - Verify: app builds for macOS, Cmd+Comma opens a separate settings window.

- [ ] 2. DashboardView settings button opens settings window on macOS <!-- id:btw83r8 -->
  - On macOS, the settings toolbar button uses SettingsLink instead of NavigationLink.
  - On iOS, NavigationLink behavior is unchanged.
  - Verify: tapping the gear icon on macOS opens the settings window; on iOS it still pushes onto the NavigationStack.
  - Blocked-by: btw83r7 (Settings scene added to TransitApp on macOS)

- [ ] 3. SettingsView back button and navigationBarBackButtonHidden removed on macOS <!-- id:btw83r9 -->
  - The custom back/dismiss toolbar button and .navigationBarBackButtonHidden(true) are removed from macOSSettings.
  - The settings window is the root view so no back button is needed at root level.
  - Verify: settings window shows no back button at root, but sub-views (ProjectEdit, Acknowledgments) show the system back button when pushed.
  - Blocked-by: btw83r7 (Settings scene added to TransitApp on macOS)

## Verification

- [ ] 4. Sub-navigation within settings window works correctly <!-- id:btw83ra -->
  - Tapping a project row navigates to ProjectEditView within the settings window.
  - Tapping Acknowledgments navigates to AcknowledgmentsView.
  - System back button returns to the settings root.
  - Verify: all settings sub-views are reachable and navigable within the settings window, not the main window.
  - Blocked-by: btw83r7 (Settings scene added to TransitApp on macOS), btw83r8 (DashboardView settings button opens settings window on macOS), btw83r9 (SettingsView back button and navigationBarBackButtonHidden removed on macOS)

- [ ] 5. Environment and data flow verified across scenes <!-- id:btw83rb -->
  - @Query results (projects list) appear in the settings window.
  - @AppStorage changes (theme picker) propagate to the main dashboard window immediately.
  - MCP settings toggle works.
  - Verify: change theme in settings window, dashboard background updates in real time.
  - Blocked-by: btw83ra (Sub-navigation within settings window works correctly)

- [ ] 6. Build succeeds on both platforms and existing tests pass <!-- id:btw83rc -->
  - make build succeeds for both iOS and macOS.
  - make test-quick passes.
  - No regressions in existing functionality.
  - Verify: clean build and green tests.
  - Blocked-by: btw83rb (Environment and data flow verified across scenes)
