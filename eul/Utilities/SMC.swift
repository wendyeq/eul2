//
// SMC.swift
// SMCKit
//
// The MIT License
//
// Copyright (C) 2014-2017  beltex <https://beltex.github.io>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

// huge credit to D0miH for new MacBook fan speed compatibility

import Foundation
import IOKit
import SharedLibrary

// ------------------------------------------------------------------------------

// MARK: Type Aliases

// ------------------------------------------------------------------------------

// http://stackoverflow.com/a/22383661

/// Floating point, unsigned, 14 bits exponent, 2 bits fraction
public typealias FPE2 = (UInt8, UInt8)

/// Floating point data type used by Apple Silicon temperature and fan keys
public typealias FLT = (UInt8, UInt8, UInt8, UInt8)

public typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8)

// ------------------------------------------------------------------------------

// MARK: Standard Library Extensions

// ------------------------------------------------------------------------------

extension UInt32 {
    init(fromBytes bytes: (UInt8, UInt8, UInt8, UInt8)) {
        // TODO: Broken up due to "Expression was too complex" error as of
        //       Swift 4.

        let byte0 = UInt32(bytes.0) << 24
        let byte1 = UInt32(bytes.1) << 16
        let byte2 = UInt32(bytes.2) << 8
        let byte3 = UInt32(bytes.3)

        self = byte0 | byte1 | byte2 | byte3
    }
}

extension Bool {
    init(fromByte byte: UInt8) {
        self = byte == 1 ? true : false
    }
}

public extension Int {
    init(fromFPE2 bytes: FPE2) {
        self = (Int(bytes.0) << 6) + (Int(bytes.1) >> 2)
    }

    init(fromFLT bytes: FLT) {
        // convert the SMCBytes to a float value
        let byteArray: [UInt8] = [bytes.0, bytes.1, bytes.2, bytes.3]
        var resultValue: Float = 0.0
        memcpy(&resultValue, byteArray, 4)
        self = Int(resultValue)
    }

    func toFPE2() -> FPE2 {
        return (UInt8(self >> 6), UInt8((self << 2) ^ ((self >> 6) << 8)))
    }
}

extension Double {
    init(fromFLT bytes: FLT) {
        let byteArray: [UInt8] = [bytes.0, bytes.1, bytes.2, bytes.3]
        var resultValue: Float = 0.0
        memcpy(&resultValue, byteArray, 4)
        self = Double(resultValue)
    }
}

// Thanks to Airspeed Velocity for the great idea!
// http://airspeedvelocity.net/2015/05/22/my-talk-at-swift-summit/
public extension FourCharCode {
    init(fromString str: String) {
        precondition(str.count == 4)

        self = str.utf8.reduce(0) { sum, character in
            sum << 8 | UInt32(character)
        }
    }

    init(fromStaticString str: StaticString) {
        precondition(str.utf8CodeUnitCount == 4)

        self = str.withUTF8Buffer { buffer in
            // TODO: Broken up due to "Expression was too complex" error as of
            //       Swift 4.

            let byte0 = UInt32(buffer[0]) << 24
            let byte1 = UInt32(buffer[1]) << 16
            let byte2 = UInt32(buffer[2]) << 8
            let byte3 = UInt32(buffer[3])

            return byte0 | byte1 | byte2 | byte3
        }
    }

    func toString() -> String {
        return String(describing: UnicodeScalar(self >> 24 & 0xFF)!) +
            String(describing: UnicodeScalar(self >> 16 & 0xFF)!) +
            String(describing: UnicodeScalar(self >> 8 & 0xFF)!) +
            String(describing: UnicodeScalar(self & 0xFF)!)
    }
}

// ------------------------------------------------------------------------------

// MARK: Defined by AppleSMC.kext

// ------------------------------------------------------------------------------

/// Defined by AppleSMC.kext
///
/// This is the predefined struct that must be passed to communicate with the
/// AppleSMC driver. While the driver is closed source, the definition of this
/// struct happened to appear in the Apple PowerManagement project at around
/// version 211, and soon after disappeared. It can be seen in the PrivateLib.c
/// file under pmconfigd. Given that it is C code, this is the closest
/// translation to Swift from a type perspective.
///
/// ### Issues
///
/// * Padding for struct alignment when passed over to C side
/// * Size of struct must be 80 bytes
/// * C array's are bridged as tuples
///
/// http://www.opensource.apple.com/source/PowerManagement/PowerManagement-211/
public struct SMCParamStruct {
    /// I/O Kit function selector
    public enum Selector: UInt8 {
        case kSMCHandleYPCEvent = 2
        case kSMCReadKey = 5
        case kSMCWriteKey = 6
        case kSMCGetKeyFromIndex = 8
        case kSMCGetKeyInfo = 9
    }

    /// Return codes for SMCParamStruct.result property
    public enum Result: UInt8 {
        case kSMCSuccess = 0
        case kSMCError = 1
        case kSMCKeyNotFound = 132
    }

    public struct SMCVersion {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    public struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    public struct SMCKeyInfoData {
        /// How many bytes written to SMCParamStruct.bytes.
        /// Must stay UInt32: IOByteCount is 8 bytes on modern SDKs and breaks
        /// the 80-byte AppleSMC struct (kIOReturnBadArgument on Apple Silicon).
        var dataSize: UInt32 = 0

        /// Type of data written to SMCParamStruct.bytes. This lets us know how
        /// to interpret it (translate it to human readable)
        var dataType: UInt32 = 0

        var dataAttributes: UInt8 = 0
    }

    /// FourCharCode telling the SMC what we want
    var key: UInt32 = 0

    var vers = SMCVersion()

    var pLimitData = SMCPLimitData()

    var keyInfo = SMCKeyInfoData()

    /// Padding for struct alignment when passed over to C side
    var padding: UInt16 = 0

    /// Result of an operation
    var result: UInt8 = 0

    var status: UInt8 = 0

    /// Method selector
    var data8: UInt8 = 0

    var data32: UInt32 = 0

    /// Data returned from the SMC
    var bytes: SMCBytes = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0))
}

// ------------------------------------------------------------------------------

// MARK: SMC Client

// ------------------------------------------------------------------------------

/// SMC data type information
public enum DataTypes {
    /// Fan information struct
    public static let FDS = DataType(type: FourCharCode(fromStaticString: "{fds"), size: 16)
    public static let Flag = DataType(type: FourCharCode(fromStaticString: "flag"), size: 1)
    /// See type aliases
    public static let FPE2 = DataType(type: FourCharCode(fromStaticString: "fpe2"), size: 2)
    public static let FLT = DataType(type: FourCharCode(fromStaticString: "flt "), size: 4)
    public static let UInt8 = DataType(type: FourCharCode(fromStaticString: "ui8 "), size: 1)
    public static let UInt32 = DataType(type: FourCharCode(fromStaticString: "ui32"), size: 4)
}

public struct SMCKey {
    let code: FourCharCode
    let info: DataType
}

public struct DataType: Equatable {
    let type: FourCharCode
    let size: UInt32
}

public func == (lhs: DataType, rhs: DataType) -> Bool {
    return lhs.type == rhs.type && lhs.size == rhs.size
}

/// Apple System Management Controller (SMC) user-space client. Works by talking
/// to the AppleSMC.kext (kernel extension), the closed source driver for the SMC.
public enum SMCKit {
    public enum SMCError: Error {
        /// AppleSMC driver not found
        case driverNotFound

        /// Failed to open a connection to the AppleSMC driver
        case failedToOpen

        /// This SMC key is not valid on this machine
        case keyNotFound(code: String)

        /// Requires root privileges
        case notPrivileged

        /// Fan speed must be > 0 && <= fanMaxSpeed
        case unsafeFanSpeed

        /// https://developer.apple.com/library/mac/qa/qa1075/_index.html
        ///
        /// - parameter kIOReturn: I/O Kit error code
        /// - parameter SMCResult: SMC specific return code
        case unknown(kIOReturn: kern_return_t, SMCResult: UInt8)
    }

    /// Connection to the SMC driver
    fileprivate static var connection: io_connect_t = 0

    /// Open connection to the SMC driver. This must be done first before any
    /// other calls
    public static func open() throws {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                  IOServiceMatching("AppleSMC"))

        if service == 0 { throw SMCError.driverNotFound }

        let result = IOServiceOpen(service, mach_task_self_, 0,
                                   &SMCKit.connection)
        IOObjectRelease(service)

        if result != kIOReturnSuccess { throw SMCError.failedToOpen }
    }

    /// Close connection to the SMC driver
    @discardableResult
    public static func close() -> Bool {
        let result = IOServiceClose(SMCKit.connection)
        return result == kIOReturnSuccess ? true : false
    }

    /// Get information about a key
    public static func keyInformation(_ key: FourCharCode) throws -> DataType {
        var inputStruct = SMCParamStruct()

        inputStruct.key = key
        inputStruct.data8 = SMCParamStruct.Selector.kSMCGetKeyInfo.rawValue

        let outputStruct = try callDriver(&inputStruct)

        return DataType(type: outputStruct.keyInfo.dataType,
                        size: outputStruct.keyInfo.dataSize)
    }

    /// Get information about the key at index
    public static func keyInformationAtIndex(_ index: Int) throws ->
        FourCharCode
    {
        var inputStruct = SMCParamStruct()

        inputStruct.data8 = SMCParamStruct.Selector.kSMCGetKeyFromIndex.rawValue
        inputStruct.data32 = UInt32(index)

        let outputStruct = try callDriver(&inputStruct)

        return outputStruct.key
    }

    /// Read data of a key
    public static func readData(_ key: SMCKey) throws -> SMCBytes {
        var inputStruct = SMCParamStruct()

        inputStruct.key = key.code
        inputStruct.keyInfo.dataSize = UInt32(key.info.size)
        inputStruct.data8 = SMCParamStruct.Selector.kSMCReadKey.rawValue

        let outputStruct = try callDriver(&inputStruct)

        return outputStruct.bytes
    }

    /// Write data for a key
    public static func writeData(_ key: SMCKey, data: SMCBytes) throws {
        var inputStruct = SMCParamStruct()

        inputStruct.key = key.code
        inputStruct.bytes = data
        inputStruct.keyInfo.dataSize = UInt32(key.info.size)
        inputStruct.data8 = SMCParamStruct.Selector.kSMCWriteKey.rawValue

        _ = try callDriver(&inputStruct)
    }

    /// Make an actual call to the SMC driver
    public static func callDriver(_ inputStruct: inout SMCParamStruct,
                                  selector: SMCParamStruct.Selector = .kSMCHandleYPCEvent)
        throws -> SMCParamStruct
    {
        assert(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct size is != 80")

        var outputStruct = SMCParamStruct()
        let inputStructSize = MemoryLayout<SMCParamStruct>.stride
        var outputStructSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(SMCKit.connection,
                                               UInt32(selector.rawValue),
                                               &inputStruct,
                                               inputStructSize,
                                               &outputStruct,
                                               &outputStructSize)

        switch (result, outputStruct.result) {
        case (kIOReturnSuccess, SMCParamStruct.Result.kSMCSuccess.rawValue):
            return outputStruct
        case (kIOReturnSuccess, SMCParamStruct.Result.kSMCKeyNotFound.rawValue):
            throw SMCError.keyNotFound(code: inputStruct.key.toString())
        case (kIOReturnNotPrivileged, _):
            throw SMCError.notPrivileged
        default:
            throw SMCError.unknown(kIOReturn: result,
                                   SMCResult: outputStruct.result)
        }
    }
}

// ------------------------------------------------------------------------------

// MARK: General

// ------------------------------------------------------------------------------

public extension SMCKit {
    /// Get all valid SMC keys for this machine
    static func allKeys() throws -> [SMCKey] {
        let count = try keyCount()
        var keys = [SMCKey]()

        for i in 0..<count {
            let key = try keyInformationAtIndex(i)
            let info = try keyInformation(key)
            keys.append(SMCKey(code: key, info: info))
        }

        return keys
    }

    /// Get the number of valid SMC keys for this machine
    static func keyCount() throws -> Int {
        let key = SMCKey(code: FourCharCode(fromStaticString: "#KEY"),
                         info: DataTypes.UInt32)

        let data = try readData(key)
        return Int(UInt32(fromBytes: (data.0, data.1, data.2, data.3)))
    }

    /// Is this key valid on this machine?
    static func isKeyFound(_ code: FourCharCode) throws -> Bool {
        do {
            _ = try keyInformation(code)
        } catch SMCError.keyNotFound { return false }

        return true
    }
}

// ------------------------------------------------------------------------------

// MARK: Temperature

// ------------------------------------------------------------------------------

/// Apple Silicon temperature keys. The list is NOT exhaustive, and the codes
/// differ by generation, so several aliases map onto the same logical sensor.
/// Names are what `SmcControl` looks up; codes are what the SMC exposes.
///
/// ### Sources
///
/// * powermetrics(1)
/// * upstream PR #275 for the M1 keys
/// * probed directly on Apple Silicon for the M2/M3/M4 keys
public enum TemperatureSensors {
    public static let CPU_PCORE = TemperatureSensor(name: "CPU_PCORE",
                                                    code: FourCharCode(fromStaticString: "Tp09"))
    public static let CPU_PCORE_ALT = TemperatureSensor(name: "CPU_PCORE_ALT",
                                                        code: FourCharCode(fromStaticString: "Tp01"))
    public static let CPU_PCORE_M3 = TemperatureSensor(name: "CPU_PCORE_M3",
                                                       code: FourCharCode(fromStaticString: "Tf04"))
    public static let CPU_ECORE = TemperatureSensor(name: "CPU_ECORE",
                                                    code: FourCharCode(fromStaticString: "Tp0T"))
    public static let CPU_ECORE_M2 = TemperatureSensor(name: "CPU_ECORE_M2",
                                                       code: FourCharCode(fromStaticString: "Tp1h"))
    public static let CPU_ECORE_M3 = TemperatureSensor(name: "CPU_ECORE_M3",
                                                       code: FourCharCode(fromStaticString: "Te05"))
    public static let CPU_PACKAGE = TemperatureSensor(name: "CPU_PACKAGE",
                                                      code: FourCharCode(fromStaticString: "Tp05"))
    public static let GPU_APPLE_SILICON = TemperatureSensor(name: "GPU_APPLE_SILICON",
                                                            code: FourCharCode(fromStaticString: "Tg05"))
    public static let GPU_APPLE_SILICON_M2 = TemperatureSensor(name: "GPU_APPLE_SILICON_M2",
                                                               code: FourCharCode(fromStaticString: "Tg0f"))
    public static let GPU_APPLE_SILICON_M3 = TemperatureSensor(name: "GPU_APPLE_SILICON_M3",
                                                               code: FourCharCode(fromStaticString: "Tf14"))
    public static let ENCLOSURE_BASE_0 =
        TemperatureSensor(name: "ENCLOSURE_BASE_0",
                          code: FourCharCode(fromStaticString: "TB0T"))
    public static let ENCLOSURE_BASE_1 =
        TemperatureSensor(name: "ENCLOSURE_BASE_1",
                          code: FourCharCode(fromStaticString: "TB1T"))
    public static let ENCLOSURE_BASE_2 =
        TemperatureSensor(name: "ENCLOSURE_BASE_2",
                          code: FourCharCode(fromStaticString: "TB2T"))
    public static let ENCLOSURE_BASE_3 =
        TemperatureSensor(name: "ENCLOSURE_BASE_3",
                          code: FourCharCode(fromStaticString: "TB3T"))
    public static let PALM_REST = TemperatureSensor(name: "PALM_REST",
                                                    code: FourCharCode(fromStaticString: "Ts0P"))
    public static let WIFI_MODULE = TemperatureSensor(name: "WIFI_MODULE",
                                                      code: FourCharCode(fromStaticString: "TW0P"))

    public static let all = [CPU_PCORE.code: CPU_PCORE,
                             CPU_PCORE_ALT.code: CPU_PCORE_ALT,
                             CPU_PCORE_M3.code: CPU_PCORE_M3,
                             CPU_ECORE.code: CPU_ECORE,
                             CPU_ECORE_M2.code: CPU_ECORE_M2,
                             CPU_ECORE_M3.code: CPU_ECORE_M3,
                             CPU_PACKAGE.code: CPU_PACKAGE,
                             GPU_APPLE_SILICON.code: GPU_APPLE_SILICON,
                             GPU_APPLE_SILICON_M2.code: GPU_APPLE_SILICON_M2,
                             GPU_APPLE_SILICON_M3.code: GPU_APPLE_SILICON_M3,
                             ENCLOSURE_BASE_0.code: ENCLOSURE_BASE_0,
                             ENCLOSURE_BASE_1.code: ENCLOSURE_BASE_1,
                             ENCLOSURE_BASE_2.code: ENCLOSURE_BASE_2,
                             ENCLOSURE_BASE_3.code: ENCLOSURE_BASE_3,
                             PALM_REST.code: PALM_REST,
                             WIFI_MODULE.code: WIFI_MODULE]
}

// MARK: Power (Apple Silicon SMC)

public struct PowerSensor {
    public let name: String
    public let code: FourCharCode
}

public enum PowerSensors {
    public static let SYSTEM_TOTAL = PowerSensor(name: "SYSTEM_TOTAL",
                                                 code: FourCharCode(fromStaticString: "PSTR"))
    public static let CPU_PACKAGE = PowerSensor(name: "CPU_PACKAGE",
                                                code: FourCharCode(fromStaticString: "PP0C"))
    public static let GPU = PowerSensor(name: "GPU",
                                        code: FourCharCode(fromStaticString: "PG0C"))

    public static let all: [PowerSensor] = [SYSTEM_TOTAL, CPU_PACKAGE, GPU]
}

public extension SMCKit {
    static func powerWatts(_ sensorCode: FourCharCode) throws -> Double {
        let info = (try? keyInformation(sensorCode)) ?? DataTypes.FLT
        let data = try readData(SMCKey(code: sensorCode, info: info))
        return Double(fromFLT: (data.0, data.1, data.2, data.3))
    }
}

public extension SMCKit {
    static func allKnownTemperatureSensors() throws ->
        [TemperatureSensor]
    {
        var sensors = [TemperatureSensor]()

        for sensor in TemperatureSensors.all.values {
            do {
                if try isKeyFound(sensor.code) { sensors.append(sensor) }
            } catch {
                continue
            }
        }

        return sensors
    }

    static func allUnknownTemperatureSensors() throws -> [TemperatureSensor] {
        let keys = try allKeys()

        return keys.filter { $0.code.toString().hasPrefix("T") &&
            $0.info == DataTypes.FLT &&
            TemperatureSensors.all[$0.code] == nil
        }
        .map { TemperatureSensor(name: "Unknown", code: $0.code) }
    }

    /// Get current temperature of a sensor
    static func temperature(_ sensorCode: FourCharCode,
                            unit: TemperatureUnit = .celius) throws -> Double
    {
        let temperatureInCelius = try celsius(for: sensorCode)

        switch unit {
        case .celius:
            return temperatureInCelius
        case .fahrenheit:
            return TemperatureUnit.toFahrenheit(temperatureInCelius)
        case .kelvin:
            return TemperatureUnit.toKelvin(temperatureInCelius)
        }
    }

    /// Apple Silicon reports every temperature key as FLT.
    private static func celsius(for sensorCode: FourCharCode) throws -> Double {
        let info = (try? keyInformation(sensorCode)) ?? DataTypes.FLT
        let data = try readData(SMCKey(code: sensorCode, info: info))
        return Double(fromFLT: (data.0, data.1, data.2, data.3))
    }
}

// ------------------------------------------------------------------------------

// MARK: Fan

// ------------------------------------------------------------------------------

public struct Fan {
    // TODO: Should we start the fan id from 1 instead of 0?
    public let id: Int
    public let name: String
    public let minSpeed: Int
    public let maxSpeed: Int
}

public extension SMCKit {
    static func allFans() throws -> [Fan] {
        let count = try fanCount()
        var fans = [Fan]()

        for i in 0..<count {
            fans.append(try SMCKit.fan(i))
        }

        return fans
    }

    static func fan(_ id: Int) throws -> Fan {
        let name = try fanName(id)
        let minSpeed = try fanMinSpeed(id)
        let maxSpeed = try fanMaxSpeed(id)
        return Fan(id: id, name: name, minSpeed: minSpeed, maxSpeed: maxSpeed)
    }

    /// Number of fans this machine has. Fanless Apple Silicon Macs report 0.
    static func fanCount() throws -> Int {
        let key = SMCKey(code: FourCharCode(fromStaticString: "FNum"),
                         info: DataTypes.UInt8)

        let data = try readData(key)
        return Int(data.0)
    }

    static func fanName(_ id: Int) throws -> String {
        let key = SMCKey(code: FourCharCode(fromString: "F\(id)ID"),
                         info: DataTypes.FDS)
        let data = try readData(key)

        // The last 12 bytes of '{fds' data type, a custom struct defined by the
        // AppleSMC.kext that is 16 bytes, contains the fan name
        let c1 = String(UnicodeScalar(data.4))
        let c2 = String(UnicodeScalar(data.5))
        let c3 = String(UnicodeScalar(data.6))
        let c4 = String(UnicodeScalar(data.7))
        let c5 = String(UnicodeScalar(data.8))
        let c6 = String(UnicodeScalar(data.9))
        let c7 = String(UnicodeScalar(data.10))
        let c8 = String(UnicodeScalar(data.11))
        let c9 = String(UnicodeScalar(data.12))
        let c10 = String(UnicodeScalar(data.13))
        let c11 = String(UnicodeScalar(data.14))
        let c12 = String(UnicodeScalar(data.15))

        let name = c1 + c2 + c3 + c4 + c5 + c6 + c7 + c8 + c9 + c10 + c11 + c12

        let characterSet = CharacterSet.whitespaces
        return name.trimmingCharacters(in: characterSet)
    }

    private static func decodeData(with code: String) throws -> Int {
        let four = FourCharCode(fromString: code)
        if let info = try? keyInformation(four) {
            let data = try readData(SMCKey(code: four, info: info))
            if info == DataTypes.FLT || info.size == 4 {
                return Int(fromFLT: (data.0, data.1, data.2, data.3))
            }
            return Int(fromFPE2: (data.0, data.1))
        }

        do {
            let key = SMCKey(
                code: FourCharCode(fromString: code),
                info: DataTypes.FPE2
            )

            let data = try readData(key)
            return Int(fromFPE2: (data.0, data.1))
        } catch SMCError.unknown(kIOReturn: 0, SMCResult: 135) {
            let key = SMCKey(
                code: FourCharCode(fromString: code),
                info: DataTypes.FLT
            )

            let data = try readData(key)
            return Int(fromFLT: (data.0, data.1, data.2, data.3))
        }
    }

    static func fanCurrentSpeed(_ id: Int) throws -> Int {
        try decodeData(with: "F\(id)Ac")
    }

    static func fanMinSpeed(_ id: Int) throws -> Int {
        try decodeData(with: "F\(id)Mn")
    }

    static func fanMaxSpeed(_ id: Int) throws -> Int {
        try decodeData(with: "F\(id)Mx")
    }

    /// Requires root privileges. By minimum we mean that OS X can interject and
    /// raise the fan speed if needed, however it will not go below this.
    ///
    /// WARNING: You are playing with hardware here, BE CAREFUL.
    ///
    /// - Throws: Of note, `SMCKit.SMCError`'s `UnsafeFanSpeed` and `NotPrivileged`
    static func fanSetMinSpeed(_ id: Int, speed: Int) throws {
        let maxSpeed = try fanMaxSpeed(id)
        if speed <= 0 || speed > maxSpeed { throw SMCError.unsafeFanSpeed }

        let data = speed.toFPE2()
        let bytes: SMCBytes = (data.0, data.1, UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                               UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                               UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                               UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                               UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                               UInt8(0), UInt8(0))

        let key = SMCKey(code: FourCharCode(fromString: "F\(id)Mn"),
                         info: DataTypes.FPE2)

        try writeData(key, data: bytes)
    }
}

// ------------------------------------------------------------------------------

// MARK: Miscellaneous

// ------------------------------------------------------------------------------

public struct batteryInfo {
    public let batteryCount: Int
    public let isACPresent: Bool
    public let isBatteryPowered: Bool
    public let isBatteryOk: Bool
    public let isCharging: Bool
}

public extension SMCKit {
    static func batteryInformation() throws -> batteryInfo {
        let batteryCountKey =
            SMCKey(code: FourCharCode(fromStaticString: "BNum"),
                   info: DataTypes.UInt8)
        let batteryPoweredKey =
            SMCKey(code: FourCharCode(fromStaticString: "BATP"),
                   info: DataTypes.Flag)
        let batteryInfoKey =
            SMCKey(code: FourCharCode(fromStaticString: "BSIn"),
                   info: DataTypes.UInt8)

        let batteryCountData = try readData(batteryCountKey)
        let batteryCount = Int(batteryCountData.0)

        let isBatteryPoweredData = try readData(batteryPoweredKey)
        let isBatteryPowered = Bool(fromByte: isBatteryPoweredData.0)

        let batteryInfoData = try readData(batteryInfoKey)
        let isCharging = batteryInfoData.0 & 1 == 1 ? true : false
        let isACPresent = (batteryInfoData.0 >> 1) & 1 == 1 ? true : false
        let isBatteryOk = (batteryInfoData.0 >> 6) & 1 == 1 ? true : false

        return batteryInfo(batteryCount: batteryCount, isACPresent: isACPresent,
                           isBatteryPowered: isBatteryPowered,
                           isBatteryOk: isBatteryOk,
                           isCharging: isCharging)
    }
}
