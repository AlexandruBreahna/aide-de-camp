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
    let data: [Event]?
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
