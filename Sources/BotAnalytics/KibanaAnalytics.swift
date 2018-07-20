import Foundation
import Jay
import Dispatch
import HTTP
import Vapor

public class KibanaAnalytics {
    
    let HttpResponse = "http_response"
    let ExceptionEvent = "exception"
    let ErrorEvent = "error"
    let WarningEvent = "warning"
    let InfoEvent = "info"
    let DebugEvent = "debug"
    let VerboseEvent = "verbose"
    
    let client: Vapor.Responder
    let analyticsIndexName: String
    let engAnalyticsIndexName: String
    let engErrorsIndexName: String
    let host: String
    let endpoint: String
    let authorization: String
    let isAnalyticsDisabled: Bool = false
    
    public init(client: Vapor.Responder,
         analyticsIndexName: String,
         engAnalyticsIndexName: String,
         engErrorsIndexName: String,
         host: String,
         endpoint: String,
         authorization: String) {
        
        self.client = client
        self.analyticsIndexName = analyticsIndexName
        self.engAnalyticsIndexName = engAnalyticsIndexName
        self.engErrorsIndexName = engErrorsIndexName
        self.host = host
        self.endpoint = endpoint
        self.authorization = authorization
    }
    
    public func logException(_ error: Error, dict: [String: Any] = [String: Any]()) {
        var payload = dict
        payload["event_type"] = ExceptionEvent
        payload["error"] = "\(error)"
        timestampAndLogEngPayload(payload, event: ExceptionEvent)
    }
    
    public func logError(_ error: String, dict: [String: Any] = [String: Any]()) {
        print(error)
        var payload = dict
        payload["error"] = error
        timestampAndLogEngPayload(payload, event: ErrorEvent)
    }
    
    public func logWarning(_ warning: String, dict: [String: Any] = [String: Any]()) {
        print("Warning: \(warning)")
        var payload = dict
        payload["error"] = warning
        timestampAndLogEngPayload(payload, event: WarningEvent)
    }
    
    public func logResponse(_ response: Response, endpoint: String, dict: [String: Any] = [String: Any](), duration: Int? = nil) {
        var payload = dict
        payload["error"] = response.json?["error.message"]?.string
        payload["endpoint"] = endpoint
        payload["status"] = response.status.reasonPhrase
        payload["duration"] = duration
        timestampAndLogEngPayload(payload, event: HttpResponse)
    }
    
    public func elkLogAnalytics(event: String, email: String, details: [String: Any] = [String:Any]()) {
        var payload = [String: Any]()
        payload["event_type"] = event
        payload["email"] = email
        for (key, value) in details {
            payload[key] = value
        }
        
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970 * 1000)
        payload["date"] = timestamp
        let eventId = "\(event)_\(timestamp)"
        
        let url = elkProductURLFor(eventId: eventId)
        self.writeKibanaEntry(url: url, event: payload)
    }
    
    public func writeKibanaEntry(url: String, event: [String: Any]) {
        DispatchQueue.global(qos: DispatchQoS.QoSClass.background).async {[weak self] in
            guard let welf = self else {
                return
            }
            
            do {
                let data = try Jay().dataFromJson(anyDictionary: event)
                let finalJSON = try JSON(bytes: data)
                let headers = [
                    HeaderKey("Content-Type"): "application/json",
                    HeaderKey("Authorization"): welf.authorization,
                    ]
                
                let result = try welf.client.put(url, query: [:], headers, finalJSON.makeBody(), through: [])
                if result.status != Status.ok && result.status != Status.created {
                    print("***ERROR writing to Kibana \(result)")
                }
            } catch let error {
                print("\(#function) Ran into exception \(error)")
            }
        }
    }
    
    public func elkURL(index: String, eventId: String) -> String {
        return "http://\(host)/\(index)/\(endpoint)/\(eventId)"
    }
    
    public func elkProductURLFor(eventId: String) -> String {
        return elkURL(index: self.analyticsIndexName, eventId: eventId)
    }
    
    public func elkEngURLFor(event: String, timestamp: Int) -> String {
        let eventId = "\(event)_\(timestamp)"
        if event == WarningEvent || event == ErrorEvent || event == ExceptionEvent {
            return elkURL(index: self.engErrorsIndexName, eventId: eventId)
        }
        return elkURL(index: self.engAnalyticsIndexName, eventId: eventId)
    }
    
    public func timestampAndLogEngPayload(_ dict: [String: Any], event: String) {
        if self.isAnalyticsDisabled {
            return
        }
        
        var payload = dict
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970 * 1000)
        payload["date"] = timestamp
        payload["event_type"] = event
        
        let url = elkEngURLFor(event: event, timestamp: timestamp)
        self.writeKibanaEntry(url: url, event: payload)
    }
}
