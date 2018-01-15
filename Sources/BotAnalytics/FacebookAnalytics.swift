import Foundation
import Jay
import Vapor
import HTTP

public class FacebookAnalytics {
    let client: Vapor.Responder
    let appID: String
    let pageID: String
    let endpoint: String
    let event: String
    public var advertiserTrackingEnabled = true
    public var applicationTrackingEnabled = true
    public var extinfo = "[\"mb1\"]"
    private var fbDefaultPayload: [String: Any] = [:]
    
    public init(client: Vapor.Responder, appID: String, pageID:String, endpoint: String, event:String) {
        self.client = client
        self.appID = appID
        self.pageID = pageID
        self.endpoint = endpoint
        self.event = event
    }
    
    public func getFbDefaultPayload() -> [String: Any] {
        if fbDefaultPayload.count == 0 {
            fbDefaultPayload = [
                "event": self.event,
                "page_id": self.pageID,
                "advertiser_tracking_enabled": self.advertiserTrackingEnabled.string,
                "application_tracking_enabled": self.applicationTrackingEnabled.string,
                "extinfo": self.extinfo,
            ]
        }
        
        return fbDefaultPayload
    }
    
    public func getFBPayloadFor(event: String, senderId: String) -> [String: Any] {
        var payload = getFbDefaultPayload()
        payload["page_scoped_user_id"] = senderId
        
        do {
            let data = try Jay().dataFromJson(anyArray: [["_eventName": event, "_valueToSum": 1, "_fb_currency": "USD"]])
            let finalJSON = try JSON(bytes: data)
            
            let customEvents = try finalJSON.makeJSON().serialize().string()
            payload["custom_events"] = customEvents
        } catch let error {
            print("\(#function) Ran into exception \(error)")
        }
        return payload
    }
    
    @discardableResult
    public func writeFBAnalyticsEntry(event: String, senderId: String) -> Bool {
        do {
            let payload = getFBPayloadFor(event: event, senderId: senderId)
            let url = "https://graph.facebook.com/\(self.appID)/\(self.endpoint)"
            let data = try Jay().dataFromJson(anyDictionary: payload)
            let finalJSON = try JSON(bytes: data)
            let node = try Node(node: finalJSON)
            let urlEncodedForm = Body.data(try! node.formURLEncoded())
            let result = try self.client.post(url, query: [:], ["Content-Type": "application/x-www-form-urlencoded"], urlEncodedForm, through: [])
            if result.status != .ok {
                print("Error when posting FB analytics, response = \(result)")
                return false
            }
        } catch let error {
            print("\(#function) Ran into exception \(error)")
            return false
        }
        
        return true
    }
}
