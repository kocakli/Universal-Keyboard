// Adapted from AMG65 Studio's UsageEngine (github.com/kocakli/amg65-studio), which adapts CodexBar (MIT);
// see THIRD_PARTY_NOTICES.md.
import Foundation
import CoreFoundation
import CryptoKit

/// Wire format deliberately contains quotas only: no credentials or account identity.
public struct UsageWindow: Codable, Sendable {
    public let usedPercent: Double?
    public let windowMinutes: Double?
    public let resetsAt: String?
    init(usedPercent: Double?, windowMinutes: Double? = nil, resetsAt: String? = nil) {
        self.usedPercent=usedPercent; self.windowMinutes=windowMinutes; self.resetsAt=resetsAt
    }
}
public struct ExtraRateWindow: Codable, Sendable {
    public let id: String
    public let title: String
    public let usageKnown: Bool
    public let window: UsageWindow
    init(id:String,title:String,usageKnown:Bool=true,window:UsageWindow) {
        self.id=id; self.title=title; self.usageKnown=usageKnown; self.window=window
    }
}
public struct UsageData: Codable, Sendable {
    public let updatedAt: String
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let tertiary: UsageWindow?
    public let extraRateWindows: [ExtraRateWindow]?
    init(updatedAt:String,primary:UsageWindow?=nil,secondary:UsageWindow?=nil,
         tertiary:UsageWindow?=nil,extraRateWindows:[ExtraRateWindow]?=nil) {
        self.updatedAt=updatedAt; self.primary=primary; self.secondary=secondary
        self.tertiary=tertiary; self.extraRateWindows=extraRateWindows
    }
}
public struct UsageFailure: Error, Codable, Sendable {
    public let code:String
    init(code:String) { self.code=code }
}
public struct ProviderResult: Codable, Sendable {
    public let provider:String
    public let usage:UsageData?
    public let rateWindowLabels:[String:String]?
    public let error:UsageFailure?
    public let accountFingerprint:String?
    init(provider:String,usage:UsageData?=nil,rateWindowLabels:[String:String]?=nil,error:UsageFailure?=nil,
         accountFingerprint:String?=nil) {
        self.provider=provider; self.usage=usage; self.rateWindowLabels=rateWindowLabels; self.error=error
        self.accountFingerprint=accountFingerprint
    }
    static func failure(_ provider:String,code:String,fingerprint:String?=nil)->Self {
        Self(provider:provider,error:UsageFailure(code:code),accountFingerprint:fingerprint)
    }
    static func success(_ provider:String,usage:UsageData,labels:[String:String]=[:],fingerprint:String?=nil)->Self {
        Self(provider:provider,usage:usage,rateWindowLabels:labels,accountFingerprint:fingerprint)
    }
    static func failed(_ provider:String,error:Error,fingerprint:String?=nil)->Self {
        if let error=error as? UsageFailure { return .failure(provider,code:error.code,fingerprint:fingerprint) }
        if error is CancellationError { return .failure(provider,code:"timeout",fingerprint:fingerprint) }
        return .failure(provider,code:"network_error",fingerprint:fingerprint)
    }
}
enum AccountFingerprint {
    static func make(provider:String,identity:String)->String {
        SHA256.hash(data:Data(("KeyMapper usage account v1\0"+provider+"\0"+identity).utf8))
            .map { String(format:"%02x",$0) }.joined()
    }
}
struct FetchContext: Sendable {
    let http:UsageHTTPClient
    let home:URL
    let environment:[String:String]
    let now:Date
    let deadline:Date
}
enum UsageDates {
    static func iso(_ date:Date)->String { ISO8601DateFormatter().string(from:date) }
    static func date(_ value:String?)->Date? {
        guard let value, value.count<=80 else { return nil }
        let formatter=ISO8601DateFormatter()
        formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        if let result=formatter.date(from:value) { return result }
        formatter.formatOptions=[.withInternetDateTime]
        return formatter.date(from:value)
    }
}
enum JSONValue {
    static func object(_ data:Data)throws->[String:Any] {
        guard data.count<=1_048_576,
              let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {
            throw UsageFailure(code:"invalid_response")
        }
        return value
    }
    static func number(_ value:Any?)->Double? {
        guard let number=value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    /// Preserve over-limit usage; the presentation layer clamps remaining quota.
    static func percent(_ value:Any?)->Double? {
        guard let value=number(value),value>=0 else { return nil }; return value
    }
    static func text(_ value:Any?,maximum:Int=160)->String? {
        guard let value=value as? String,!value.isEmpty,value.count<=maximum,
              !value.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) else { return nil }
        return value
    }
    static func jwt(_ token:String)->[String:Any]? {
        let parts=token.split(separator:".",omittingEmptySubsequences:false)
        guard parts.count==3,parts[1].count<=32_768 else { return nil }
        var raw=String(parts[1]).replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        raw += String(repeating:"=",count:(4-raw.count%4)%4)
        guard let data=Data(base64Encoded:raw) else { return nil }
        return try? object(data)
    }
}
