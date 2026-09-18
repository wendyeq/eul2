//
//  SmcControl.swift
//  eul
//
//  Created by Gao Sun on 2020/6/27.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Darwin
import Foundation
import SharedLibrary
import SwiftyJSON

class SmcControl: Refreshable {
    static var shared = SmcControl()

    var sensors: [TemperatureData] = []
    var fans: [FanData] = []
    var tempUnit: TemperatureUnit = .celius
    private var hidBackedSensorNames = Set<String>()

    /// Performance cores, falling back to the package sensor.
    var cpuCoreTemperature: Double? {
        firstPositiveTemp(prefix: "CPU_PCORE")
            ?? firstPositiveTemp(named: ["CPU_PACKAGE"])
    }

    /// Efficiency cores. Used when the performance cores report nothing.
    var cpuEfficiencyTemperature: Double? {
        firstPositiveTemp(prefix: "CPU_ECORE")
    }

    var gpuTemperature: Double? {
        firstPositiveTemp(prefix: "GPU_APPLE_SILICON")
    }

    var palmRestTemperature: Double? {
        firstPositiveTemp(named: ["PALM_REST"])
    }

    var enclosureTemperature: Double? {
        ["ENCLOSURE_BASE_0", "ENCLOSURE_BASE_1", "ENCLOSURE_BASE_2"]
            .compactMap { firstPositiveTemp(named: [$0]) }
            .max()
    }

    var ssdTemperature: Double? {
        firstPositiveTemp(named: ["SSD_NAND"])
    }

    var wifiModuleTemperature: Double? {
        firstPositiveTemp(named: ["WIFI_MODULE"])
    }

    private(set) var systemPowerW: Double?
    private(set) var cpuPowerW: Double?
    private(set) var gpuPowerW: Double?

    private var availablePowerSensors: [PowerSensor] = []

    func formatPower(_ watts: Double) -> String {
        if watts < 20 {
            return String(format: "%.1f W", watts)
        }
        return String(format: "%.0f W", watts)
    }

    var isFanValid: Bool {
        fans.count > 0
    }

    func formatTemp(_ value: Double) -> String {
        String(format: "%.0f°\(tempUnit == .celius ? "C" : "F")", value)
    }

    init() {
        do {
            try SMCKit.open()
        } catch {
            print("SMC init error", error)
            applyHIDFallbackIfNeeded()
            return
        }

        do {
            sensors = try SMCKit.allKnownTemperatureSensors().map { .init(sensor: $0) }
        } catch {
            print("SMC sensor init error", error)
        }

        if let ssdCode = Self.discoverSSDTemperatureCode() {
            let ssdSensor = TemperatureSensor(name: "SSD_NAND", code: ssdCode)
            if !sensors.contains(where: { $0.sensor.code == ssdCode }) {
                sensors.append(TemperatureData(sensor: ssdSensor))
            }
        }

        availablePowerSensors = PowerSensors.all.filter { sensor in
            (try? SMCKit.isKeyFound(sensor.code)) ?? false
        }

        do {
            fans = try (0..<SMCKit.fanCount()).map { FanData(
                id: $0,
                minSpeed: try? SMCKit.fanMinSpeed($0),
                maxSpeed: try? SMCKit.fanMaxSpeed($0)
            ) }
        } catch {
            print("SMC fan init error", error)
        }

        print(
            "SMC init sensors",
            sensors.map(\.sensor.name),
            "fans",
            fans.count
        )
        if sensors.isEmpty {
            applyHIDFallbackIfNeeded()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func subscribe() {
        initObserver(for: .SMCShouldRefresh)
    }

    func close() {
        SMCKit.close()
    }

    @objc func refresh() {
        for sensor in sensors where !hidBackedSensorNames.contains(sensor.sensor.name) {
            do {
                sensor.temp = try SMCKit.temperature(sensor.sensor.code, unit: tempUnit)
            } catch {
                sensor.temp = 0
                print("error while getting temperature", error)
            }
        }
        applyHIDFallbackIfNeeded()
        fans = fans.map {
            FanData(
                id: $0.id,
                currentSpeed: try? SMCKit.fanCurrentSpeed($0.id),
                minSpeed: $0.minSpeed,
                maxSpeed: $0.maxSpeed
            )
        }
        systemPowerW = readPower(named: "SYSTEM_TOTAL")
        cpuPowerW = readPower(named: "CPU_PACKAGE")
        gpuPowerW = readPower(named: "GPU")
        AppleSiliconIOReport.shared.refreshIfNeeded()
        Print(
            "SMC refresh cpuCore",
            cpuCoreTemperature as Any,
            "cpuEfficiency",
            cpuEfficiencyTemperature as Any,
            "gpu",
            gpuTemperature as Any,
            "fans",
            fans.map { $0.currentSpeed as Any }
        )
        NotificationCenter.default.post(name: .StoreShouldRefresh, object: nil)
    }

    private func firstPositiveTemp(named names: [String]) -> Double? {
        sensors.first(where: { names.contains($0.sensor.name) && $0.temp > 0 })?.temp
    }

    private func firstPositiveTemp(prefix: String) -> Double? {
        sensors.first(where: { $0.sensor.name.hasPrefix(prefix) && $0.temp > 0 })?.temp
    }

    private static func discoverSSDTemperatureCode() -> FourCharCode? {
        for scalar in UnicodeScalar("A").value...UnicodeScalar("Z").value {
            let letter = String(UnicodeScalar(scalar)!)
            let code = FourCharCode(fromString: "TH0\(letter)")
            if (try? SMCKit.isKeyFound(code)) ?? false {
                return code
            }
        }
        return nil
    }

    private func readPower(named name: String) -> Double? {
        guard let sensor = availablePowerSensors.first(where: { $0.name == name }) else {
            return nil
        }
        guard let watts = try? SMCKit.powerWatts(sensor.code), watts > 0, watts < 500 else {
            return nil
        }
        return watts
    }

    private func applyHIDFallbackIfNeeded() {
        let needCPU = (cpuCoreTemperature ?? 0) <= 0 && (cpuEfficiencyTemperature ?? 0) <= 0
        let needGPU = (gpuTemperature ?? 0) <= 0
        guard needCPU || needGPU else { return }

        let hid = AppleSiliconHIDTemperature.read()
        if needCPU, let cpu = hid.cpu, cpu > 0 {
            upsertSensor(TemperatureSensors.CPU_PACKAGE, temp: convertedHIDTemp(cpu))
            print("HID CPU fallback", cpu)
        }
        if needGPU, let gpu = hid.gpu, gpu > 0 {
            upsertSensor(TemperatureSensors.GPU_APPLE_SILICON, temp: convertedHIDTemp(gpu))
            print("HID GPU fallback", gpu)
        }
    }

    private func convertedHIDTemp(_ celsius: Double) -> Double {
        switch tempUnit {
        case .celius:
            return celsius
        case .fahrenheit:
            return TemperatureUnit.toFahrenheit(celsius)
        case .kelvin:
            return TemperatureUnit.toKelvin(celsius)
        }
    }

    private func upsertSensor(_ sensor: TemperatureSensor, temp: Double) {
        hidBackedSensorNames.insert(sensor.name)
        if let existing = sensors.first(where: { $0.sensor.name == sensor.name }) {
            existing.temp = temp
        } else {
            sensors.append(TemperatureData(sensor: sensor, temp: temp))
        }
    }
}

/// Private IOHID temperature path from upstream PR #279, used only when SMC keys
/// are missing. Fans still go through AppleSMC.
private enum AppleSiliconHIDTemperature {
    private static let kIOHIDEventTypeTemperature = 15
    private static let kIOHIDEventFieldTemperatureLevel = 15 << 16

    private static var client: OpaquePointer?

    static func read() -> (cpu: Double?, gpu: Double?) {
        guard let client = cachedClient() else {
            return (nil, nil)
        }

        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        guard
            let handle = handle,
            let symCopyServices = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
            let symCopyProperty = dlsym(handle, "IOHIDServiceClientCopyProperty"),
            let symCopyEvent = dlsym(handle, "IOHIDServiceClientCopyEvent"),
            let symGetFloat = dlsym(handle, "IOHIDEventGetFloatValue")
        else {
            return (nil, nil)
        }

        let copyServices = unsafeBitCast(symCopyServices, to: (@convention(c) (OpaquePointer) -> CFTypeRef?).self)
        let copyProperty = unsafeBitCast(symCopyProperty, to: (@convention(c) (OpaquePointer, CFString) -> CFTypeRef?).self)
        let copyEvent = unsafeBitCast(symCopyEvent, to: (@convention(c) (OpaquePointer, UInt32, OpaquePointer?, UInt32) -> OpaquePointer?).self)
        let getFloat = unsafeBitCast(symGetFloat, to: (@convention(c) (OpaquePointer, UInt32) -> Double).self)

        guard
            let servicesCF = copyServices(client),
            let services = servicesCF as? [AnyObject]
        else {
            return (nil, nil)
        }

        var cpuMax: Double = 0
        var gpuMax: Double = 0
        for serviceObj in services {
            let service = OpaquePointer(Unmanaged.passUnretained(serviceObj).toOpaque())
            guard let name = copyProperty(service, "Product" as CFString) as? String else {
                continue
            }
            let folded = name.lowercased()
            let isCPU = folded.contains("tdie")
                || folded.contains("pacc")
                || folded.contains("eacc")
                || folded.contains("cpu")
                || folded.contains("soc mtr")
            let isGPU = folded.contains("gpu")
            guard isCPU || isGPU else { continue }

            guard let event = copyEvent(service, UInt32(kIOHIDEventTypeTemperature), nil, 0) else {
                continue
            }
            let temp = getFloat(event, UInt32(kIOHIDEventFieldTemperatureLevel))
            guard temp > 0, temp < 150 else { continue }
            if isCPU {
                cpuMax = max(cpuMax, temp)
            }
            if isGPU {
                gpuMax = max(gpuMax, temp)
            }
        }

        return (cpuMax > 0 ? cpuMax : nil, gpuMax > 0 ? gpuMax : nil)
    }

    private static func cachedClient() -> OpaquePointer? {
        if let client = client {
            return client
        }

        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        guard let handle = handle, let symCreate = dlsym(handle, "IOHIDEventSystemClientCreate") else {
            return nil
        }
        let create = unsafeBitCast(symCreate, to: (@convention(c) (CFAllocator?) -> OpaquePointer?).self)
        guard let created = create(kCFAllocatorDefault) else {
            return nil
        }
        if let symMatch = dlsym(handle, "IOHIDEventSystemClientSetMatching") {
            let setMatching = unsafeBitCast(symMatch, to: (@convention(c) (OpaquePointer, CFDictionary) -> Void).self)
            setMatching(created, [
                "PrimaryUsagePage": 0xFF00,
                "PrimaryUsage": 5,
            ] as CFDictionary)
        }
        client = created
        return created
    }
}

extension TemperatureUnit {
    var description: String {
        switch self {
        case .celius:
            return "temp.celsius".localized()
        case .fahrenheit:
            return "temp.fahrenheit".localized()
        case .kelvin:
            return "temp.kelvin".localized()
        }
    }
}

extension Fan: JSONCodabble {
    init?(json: JSON) {
        guard
            let id = json["id"].int,
            let name = json["name"].string,
            let minSpeed = json["id"].int,
            let maxSpeed = json["id"].int
        else {
            return nil
        }
        self.id = id
        self.name = name
        self.minSpeed = minSpeed
        self.maxSpeed = maxSpeed
    }

    var json: JSON {
        JSON([
            "id": id,
            "name": name,
            "minSpeed": minSpeed,
            "maxSpeed": maxSpeed,
        ])
    }
}

extension Double {
    var temperatureString: String {
        SmcControl.shared.formatTemp(self)
    }
}
