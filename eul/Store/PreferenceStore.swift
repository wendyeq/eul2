//
//  PreferenceStore.swift
//  eul
//
//  Created by Gao Sun on 2020/8/15.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Cocoa
import Combine
import Foundation
import Localize_Swift
import SharedLibrary
import SwiftyJSON
import WidgetKit

class PreferenceStore: ObservableObject {
    enum UpgradeMethod: String, CaseIterable {
        case none
        case showInStatusBar
        case autoUpdate
    }

    static var availableLanguages: [String] {
        Localize.availableLanguages().filter { $0 != "Base" }
    }

    private let userDefaultsKey = "preference"
    private let repo = "wendyeq/eul2"
    private var cancellable: AnyCancellable?
    var repoURL: URL? {
        URL(string: "https://github.com/\(repo)")
    }

    var latestReleaseURL: URL? {
        URL(string: "https://github.com/\(repo)/releases/latest")
    }

    var version: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    @Published var temperatureUnit = TemperatureUnit.celius {
        willSet {
            SmcControl.shared.tempUnit = newValue
        }
    }

    @Published var language = Localize.currentLanguage() {
        willSet {
            Localize.setCurrentLanguage(newValue)
        }
    }

    @Published var textDisplay = Preference.TextDisplay.compact
    @Published var fontDesign: Preference.FontDesign = .default
    @Published var smcRefreshRate = 3
    @Published var networkRefreshRate = 3
    @Published var quotaRefreshRate = 1
    @Published var showIcon = true
    @Published var showCPUTopActivities = true
    @Published var showRAMTopActivities = false
    @Published var showNetworkTopActivities = false
    @Published var showCursorQuota = true
    @Published var showGrokQuota = true
    @Published var showCodexQuota = true
    @Published var quotaProviderOrder: [String] = Preference.QuotaProvider.defaultOrder.map(\.rawValue)
    @Published var cpuMenuDisplay: Preference.CpuMenuDisplay = .usagePercentage
    @Published var checkStatusItemVisibility = true
    @Published var upgradeMethod = UpgradeMethod.showInStatusBar
    @Published var isUpdateAvailable: Bool? = false
    @Published var checkUpdateFailed = true
    @Published var appearanceMode = Preference.appearance.auto
    @Published var mcpHubEnabled = false

    var json: JSON {
        JSON([
            "temperatureUnit": temperatureUnit.rawValue,
            "language": language,
            "textDisplay": textDisplay.rawValue,
            "fontDesign": fontDesign.rawValue,
            "smcRefreshRate": smcRefreshRate,
            "networkRefreshRate": networkRefreshRate,
            "quotaRefreshRate": quotaRefreshRate,
            "showIcon": showIcon,
            "showCPUTopActivities": showCPUTopActivities,
            "showRAMTopActivities": showRAMTopActivities,
            "showNetworkTopActivities": showNetworkTopActivities,
            "showCursorQuota": showCursorQuota,
            "showGrokQuota": showGrokQuota,
            "showCodexQuota": showCodexQuota,
            "quotaProviderOrder": orderedQuotaProviders.map(\.rawValue),
            "cpuMenuDisplay": cpuMenuDisplay.rawValue,
            "checkStatusItemVisibility": checkStatusItemVisibility,
            "appearance": appearanceMode.rawValue,
            "upgradeMethod": upgradeMethod.rawValue,
            "mcpHubEnabled": mcpHubEnabled,

        ])
    }

    init() {
        loadFromDefaults()
        writeToContainer()

        cancellable = objectWillChange.sink {
            DispatchQueue.main.async {
                self.saveToDefaults()
                self.writeToContainer()
            }
        }
    }

    var orderedQuotaProviders: [Preference.QuotaProvider] {
        Self.normalizedQuotaOrder(quotaProviderOrder.compactMap(Preference.QuotaProvider.init(rawValue:)))
    }

    func isQuotaProviderVisible(_ provider: Preference.QuotaProvider) -> Bool {
        switch provider {
        case .cursor:
            return showCursorQuota
        case .grok:
            return showGrokQuota
        case .codex:
            return showCodexQuota
        }
    }

    func setQuotaProviderVisible(_ provider: Preference.QuotaProvider, visible: Bool) {
        switch provider {
        case .cursor:
            showCursorQuota = visible
        case .grok:
            showGrokQuota = visible
        case .codex:
            showCodexQuota = visible
        }
    }

    func moveQuotaProvider(from offset: Int, to destination: Int) {
        var order = orderedQuotaProviders
        guard order.indices.contains(offset), order.indices.contains(destination), offset != destination else {
            return
        }
        let item = order.remove(at: offset)
        order.insert(item, at: destination)
        quotaProviderOrder = order.map(\.rawValue)
    }

    private static func normalizedQuotaOrder(_ input: [Preference.QuotaProvider]) -> [Preference.QuotaProvider] {
        var result: [Preference.QuotaProvider] = []
        for provider in input where !result.contains(provider) {
            result.append(provider)
        }
        for provider in Preference.QuotaProvider.defaultOrder where !result.contains(provider) {
            result.append(provider)
        }
        return result
    }

    func checkUpdate() {
        isUpdateAvailable = nil
        checkUpdateFailed = false

        let session = URLSession.shared
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")

        if let url = url {
            let task = session.dataTask(with: url) { data, _, error in
                DispatchQueue.main.async {
                    if
                        error == nil,
                        let version = self.version,
                        let tagName = JSON(data as Any)["tag_name"].string,
                        "v\(version)".compare(tagName, options: .numeric) == .orderedAscending
                    {
                        self.isUpdateAvailable = true

                        if self.upgradeMethod == .autoUpdate {
                            AutoUpdate.run()
                        }
                    } else {
                        self.isUpdateAvailable = false
                    }
                }
            }
            task.resume()
        } else {
            isUpdateAvailable = false
            checkUpdateFailed = true
        }
    }

    func loadFromDefaults() {
        if let raw = UserDefaults.standard.data(forKey: userDefaultsKey) {
            do {
                let data = try JSON(data: raw)

                print("⚙️ loaded data from user defaults", userDefaultsKey, data)

                if let raw = data["temperatureUnit"].string, let value = TemperatureUnit(rawValue: raw) {
                    temperatureUnit = value
                }
                if let value = data["language"].string {
                    language = value
                }
                if let raw = data["textDisplay"].string, let value = Preference.TextDisplay(rawValue: raw) {
                    textDisplay = value
                }
                if let value = data["showIcon"].bool {
                    showIcon = value
                }
                if let raw = data["fontDesign"].string, let value = Preference.FontDesign(rawValue: raw) {
                    fontDesign = value
                }
                if let value = data["smcRefreshRate"].int {
                    smcRefreshRate = value
                }
                if let value = data["networkRefreshRate"].int {
                    networkRefreshRate = value
                }
                if let value = data["quotaRefreshRate"].int, QuotaStore.allowedRefreshMinutes.contains(value) {
                    quotaRefreshRate = value
                }
                if let value = data["showCPUTopActivities"].bool {
                    showCPUTopActivities = value
                }
                if let value = data["showRAMTopActivities"].bool {
                    showRAMTopActivities = value
                }
                if let value = data["showNetworkTopActivities"].bool {
                    showNetworkTopActivities = value
                }
                if let value = data["showCursorQuota"].bool {
                    showCursorQuota = value
                }
                if let value = data["showGrokQuota"].bool {
                    showGrokQuota = value
                }
                if let value = data["showCodexQuota"].bool {
                    showCodexQuota = value
                }
                if let rawOrder = data["quotaProviderOrder"].array {
                    let parsed = rawOrder.compactMap { Preference.QuotaProvider(rawValue: $0.stringValue) }
                    if !parsed.isEmpty {
                        quotaProviderOrder = Self.normalizedQuotaOrder(parsed).map(\.rawValue)
                    }
                }
                if let raw = data["cpuMenuDisplay"].string, let value = Preference.CpuMenuDisplay(rawValue: raw) {
                    cpuMenuDisplay = value
                }
                if let value = data["checkStatusItemVisibility"].bool {
                    checkStatusItemVisibility = value
                }
                if let raw = data["appearance"].string, let value = Preference.appearance(rawValue: raw) {
                    appearanceMode = value
                }
                if let raw = data["upgradeMethod"].string, let value = UpgradeMethod(rawValue: raw) {
                    upgradeMethod = value
                }
                if let value = data["mcpHubEnabled"].bool {
                    mcpHubEnabled = value
                }
            } catch {
                print("Unable to get preference data from user defaults")
            }
        }
    }

    func saveToDefaults() {
        do {
            let data = try json.rawData()
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Unable to save preference")
        }
    }

    func writeToContainer() {
        Container.set(PreferenceEntry(temperatureUnit: temperatureUnit))
        if #available(OSX 11, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
