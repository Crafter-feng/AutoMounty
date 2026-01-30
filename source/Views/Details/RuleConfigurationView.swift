import SwiftUI

struct RuleConfigurationView: View {
    @Binding var profile: MountProfile
    let runningApps: [String]
    let installedApps: [String]
    
    var body: some View {
        Section(LocalizedStringKey("Mount Rules")) {
            // Auto Mount Toggle
            Toggle(LocalizedStringKey("Auto Mount"), isOn: $profile.autoMount)
            
            if profile.autoMount {
                VStack(alignment: .leading, spacing: 12) {
                    // Logic Header
                    HStack {
                        Text(LocalizedStringKey("Mount shares if"))
                            .foregroundColor(.secondary)
                        Picker("", selection: $profile.ruleLogic) {
                            ForEach(RuleLogic.allCases) { logic in
                                Text(logic.localizedName).tag(logic)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                        Text(LocalizedStringKey("of the following are true:"))
                            .foregroundColor(.secondary)
                    }
                    .font(.callout)
                    
                    // Rules Grid
                    if profile.rules.isEmpty {
                        Text(LocalizedStringKey("No rules configured (Matches Any Network)"))
                            .italic()
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                            // Header
                            GridRow {
                                Text(LocalizedStringKey("Type")).font(.caption).foregroundStyle(.secondary)
                                Text(LocalizedStringKey("Condition")).font(.caption).foregroundStyle(.secondary)
                                Text(LocalizedStringKey("Value")).font(.caption).foregroundStyle(.secondary)
                                Color.clear // Spacer for delete button
                                    .gridColumnAlignment(.center)
                            }
                            
                            ForEach($profile.rules) { $rule in
                                RuleRow(rule: $rule, runningApps: runningApps, installedApps: installedApps) {
                                    if let index = profile.rules.firstIndex(where: { $0.id == rule.id }) {
                                        profile.rules.remove(at: index)
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                    }
                    
                    // Add Rule Button
                    Button(action: {
                        // Add a default WiFi rule
                        let newRule = MountRule(type: .wifi, operator: .equals, value: "")
                        profile.rules.append(newRule)
                    }) {
                        Label(LocalizedStringKey("Add Rule"), systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
    }
}

struct RuleRow: View {
    @Binding var rule: MountRule
    let runningApps: [String]
    let installedApps: [String]
    let onRemove: () -> Void
    
    @State private var isAppPickerPresented = false
    @State private var appSearchText = ""
    @State private var isVPNPickerPresented = false
    
    var body: some View {
        GridRow {
            // Type Picker
            Picker("", selection: $rule.type) {
                ForEach(RuleType.allCases) { type in
                    Text(type.localizedName).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            
            // Operator Picker
            Picker("", selection: $rule.operator) {
                ForEach(RuleOperator.allCases) { op in
                    Text(op.localizedName).tag(op)
                }
            }
            .labelsHidden()
            .frame(width: 90)
            
            // Value Input
            Group {
                if rule.type == .wifi {
                    TextField(LocalizedStringKey("SSID"), text: $rule.value)
                        .textFieldStyle(.roundedBorder)
                } else if rule.type == .app {
                    appPicker
                } else if rule.type == .vpn {
                    vpnPicker
                } else {
                    TextField(LocalizedStringKey("Value"), text: $rule.value)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .frame(minWidth: 150)
            
            // Delete Button
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("Delete this rule"))
        }
    }
    
    var appPicker: some View {
        let filteredRunningApps = runningApps.filter { appSearchText.isEmpty || $0.localizedCaseInsensitiveContains(appSearchText) }
        let filteredInstalledApps = installedApps.filter { appSearchText.isEmpty || $0.localizedCaseInsensitiveContains(appSearchText) }
        
        return HStack(spacing: 4) {
            TextField(LocalizedStringKey("App Name"), text: $rule.value)
                .textFieldStyle(.roundedBorder)
            
            Button {
                isAppPickerPresented.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20)
            .popover(isPresented: $isAppPickerPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: $appSearchText, prompt: Text(LocalizedStringKey("Search Apps")))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if filteredRunningApps.isEmpty && filteredInstalledApps.isEmpty {
                                Text(LocalizedStringKey("No Matching Apps"))
                                    .foregroundColor(.secondary)
                            } else {
                                if !filteredRunningApps.isEmpty {
                                    Text(LocalizedStringKey("Running Apps"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    ForEach(filteredRunningApps, id: \.self) { app in
                                        Button(app) {
                                            rule.value = app
                                            isAppPickerPresented = false
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 4)
                                    }
                                }
                                if !filteredRunningApps.isEmpty && !filteredInstalledApps.isEmpty {
                                    Divider()
                                }
                                if !filteredInstalledApps.isEmpty {
                                    Text(LocalizedStringKey("Installed Apps"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    ForEach(filteredInstalledApps, id: \.self) { app in
                                        Button(app) {
                                            rule.value = app
                                            isAppPickerPresented = false
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 4)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
                .padding(10)
            }
        }
        .onChange(of: isAppPickerPresented) { _, newValue in
            if newValue {
                appSearchText = ""
            }
        }
    }
    
    var vpnPicker: some View {
        HStack(spacing: 4) {
            TextField(LocalizedStringKey("Interface"), text: $rule.value, prompt: Text(LocalizedStringKey("Empty for Any")))
                .textFieldStyle(.roundedBorder)
            
            Button {
                isVPNPickerPresented.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20)
            .popover(isPresented: $isVPNPickerPresented, arrowEdge: .bottom) {
                let interfaces = NetworkService.shared.getAvailableVPNInterfaces()
                VStack(alignment: .leading, spacing: 6) {
                    if interfaces.isEmpty {
                        Text(LocalizedStringKey("No VPN Interfaces Found"))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(interfaces, id: \.self) { interface in
                            Button(interface) {
                                rule.value = interface
                                isVPNPickerPresented = false
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(10)
            }
        }
    }
}
