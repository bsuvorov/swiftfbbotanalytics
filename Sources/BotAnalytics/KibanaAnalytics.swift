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
    let host: String
    let endpoint: String
    let authorization: String
    let isAnalyticsDisabled: Bool = false
    
    init(client: Vapor.Responder,
         analyticsIndexName: String,
         host: String,
         endpoint: String,
         authorization: String) {
        
        self.client = client
        self.analyticsIndexName = analyticsIndexName
        self.host = host
        self.endpoint = endpoint
        self.authorization = authorization
    }
    
    func logException(_ error: Error, dict: [String: Any] = [String: Any]()) {
        var payload = dict
        payload["event_type"] = ExceptionEvent
        payload["error"] = "\(error)"
        timestampAndLogEngPayload(payload, event: ExceptionEvent)
    }
    
    func logError(_ error: String, dict: [String: Any] = [String: Any]()) {
        print(error)
        var payload = dict
        payload["error"] = error
        timestampAndLogEngPayload(payload, event: ErrorEvent)
    }
    
    func logWarning(_ warning: String, dict: [String: Any] = [String: Any]()) {
        print("Warning: \(warning)")
        var payload = dict
        payload["error"] = warning
        timestampAndLogEngPayload(payload, event: WarningEvent)
    }
    
    func logResponse(_ response: Response, endpoint: String, dict: [String: Any] = [String: Any](), duration: Int? = nil) {
        var payload = dict
        payload["error"] = response.json?["error.message"]?.string
        payload["endpoint"] = endpoint
        payload["status"] = response.status.reasonPhrase
        payload["duration"] = duration
        timestampAndLogEngPayload(payload, event: HttpResponse)
    }
    
    func elkLogAnalytics(event: String, email: String, details: [String: Any] = [String:Any]()) {
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
        let index = self.analyticsIndexName
        
        let url = elkURL(index: index, eventId: eventId)
        self.writeKibanaEntry(url: url, event: payload)
    }
    
    func writeKibanaEntry(url: String, event: [String: Any]) {
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
    
    func elkURL(index: String, eventId: String) -> String {
        return "http://\(host)/\(index)/\(endpoint)/\(eventId)"
    }
    
    func elkEngURLFor(event: String, timestamp: Int) -> String {
        let eventId = "\(event)_\(timestamp)"
        let index = self.analyticsIndexName
        return elkURL(index: index, eventId: eventId)
    }
    
    func timestampAndLogEngPayload(_ dict: [String: Any], event: String) {
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
