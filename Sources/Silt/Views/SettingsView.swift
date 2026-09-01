import SwiftUI

struct SettingsControls: View {
    @Binding var appearanceRaw: String
    @Binding var protectedLocations: Bool
    @Binding var showDisableProtectionConfirmation: Bool

    var body: some View {
        Picker("Appearance", selection: $appearanceRaw) {
            ForEach(Appearance.allCases) { option in
                Label(option.title, systemImage: option.symbol).tag(option.rawValue)
            }
        }
        .pickerStyle(.inline)

        Divider()

        Toggle("Protect personal folders", isOn: Binding(
            get: { protectedLocations },
            set: { enabled in
                if enabled { protectedLocations = true }
                else { showDisableProtectionConfirmation = true }
            }
        ))
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("protectedLocations") private var protectedLocations = true
    @State private var showDisableProtectionConfirmation = false

    var body: some View {
        Form {
            SettingsControls(appearanceRaw: $appearanceRaw,
                             protectedLocations: $protectedLocations,
                             showDisableProtectionConfirmation: $showDisableProtectionConfirmation)
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 190)
        .alert("Turn off personal-folder protection?", isPresented: $showDisableProtectionConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Turn Off Protection", role: .destructive) { protectedLocations = false }
                .tint(Theme.danger)
        } message: {
            Text("Silt will no longer refuse to list or trash items inside Documents, Desktop, Downloads, Photos, .ssh, and the rest of the protected-location list. Hand-picked files remain Trash-only, but caches may be deleted permanently.")
        }
        .onAppear { SafetyGuard.protectedLocationsEnabled = protectedLocations }
        .onChange(of: protectedLocations) { _, enabled in
            SafetyGuard.protectedLocationsEnabled = enabled
        }
    }
}
