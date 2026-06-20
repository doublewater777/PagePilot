//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

struct VolumeKeySettingsView: View {
    @AppStorage(VolumeKeyService.volumeKeyEnabledKey) private var volumeKeyEnabled = false
    @AppStorage(VolumeKeyService.volumeKeyMappingKey) private var volumeKeyMapping = VolumeKeyService.defaultVolumeKeyMapping.rawValue

    var body: some View {
        HStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }

            List {
                toggleSection
                explanationSection
                mappingSection
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 600 : .infinity)

            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("settings_volume_key_turn_page", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var toggleSection: some View {
        Section {
            Toggle(isOn: $volumeKeyEnabled) {
                Text(NSLocalizedString("settings_volume_key_turn_page", comment: ""))
            }
        }
    }

    private var explanationSection: some View {
        Section {
            Text(NSLocalizedString("settings_volume_key_explanation", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private var mappingSection: some View {
        Section {
            Picker(selection: volumeKeyMappingBinding) {
                ForEach(VolumeKeyMapping.allCases) { mapping in
                    Text(mapping.localizedName).tag(mapping)
                }
            } label: {
                Text(NSLocalizedString("settings_volume_key_mapping_title", comment: ""))
            }
            .pickerStyle(.menu)
        }
    }

    private var volumeKeyMappingBinding: Binding<VolumeKeyMapping> {
        Binding(
            get: {
                VolumeKeyMapping(rawValue: volumeKeyMapping) ?? .downForwardUpBackward
            },
            set: { newValue in
                volumeKeyMapping = newValue.rawValue
            }
        )
    }
}

#Preview {
    NavigationView {
        VolumeKeySettingsView()
    }
    .navigationViewStyle(.stack)
}
