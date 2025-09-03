//
//  FunctionCall.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 30.08.25.
//

import Foundation

struct FunctionCall {
    struct Function {
        let name: String
        let arguments: String
    }

    let id: String
    let function: Function
}
