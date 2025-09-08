//
//  EventResponse.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 07.09.25.
//

import Foundation

// MARK: - Response Models following Codable best practices
struct EventResponse: Codable {
    let success: Bool
    let requestId: String?
    let data: [[String: AnyCodable]]?
    let metadata: ResponseMetadata?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case requestId = "request_id"
        case data
        case metadata
        case error
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init<T>(_ value: T?) {
        self.value = value ?? ()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = ()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unable to decode"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else {
            try container.encodeNil()
        }
    }
}

struct Event: Codable, Identifiable {
    let id: String  // Server-generated
    let eventType: String
    let date: String
    let hour: String
    let calories: Double?
    let proteins: Double?
    let fat: Double?
    let carbs: Double?
    let workout: String?
    let exercise: String?
    let sets: Int?
    let reps: Int?
    let weight: Double?
    let category: String?
    let value: Double?
    let currency: String?
    let comments: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case date, hour, calories, proteins, fat, carbs
        case workout, exercise, sets, reps, weight
        case category, value, currency, comments
    }
}

struct ResponseMetadata: Codable {
    let count: Int
    let aggregations: Aggregations?
    let dateRange: DateRange?
    
    enum CodingKeys: String, CodingKey {
        case count, aggregations
        case dateRange = "date_range"
    }
}

struct Aggregations: Codable {
    let totalCalories: Double?
    let averageCalories: Double?
    let totalValue: Double?
    let totalWorkouts: Int?
    
    enum CodingKeys: String, CodingKey {
        case totalCalories = "total_calories"
        case averageCalories = "average_calories"
        case totalValue = "total_value"
        case totalWorkouts = "total_workouts"
    }
}

struct DateRange: Codable {
    let from: String
    let to: String
}
