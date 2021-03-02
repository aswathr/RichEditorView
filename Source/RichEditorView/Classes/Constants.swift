//
//  Constants.swift
//  
//
//  Created by Aswath on 02/03/21.
//

import Foundation

public struct REVConstants {
    
    public var moduleBundle: Bundle { Bundle.module }
    
    public static var defaultSetupURLRequest: URLRequest? {
        
        if let filePath = Bundle.module.path(forResource: "rich_editor", ofType: "html") {
            let url = URL(fileURLWithPath: filePath, isDirectory: false)
            return URLRequest(url: url)
        }
        
        return nil
    }
    
    public static var firstPersonSetupURLRequest: URLRequest? {
        
        if let filePath = Bundle.module.path(forResource: "rich_editor_first_person", ofType: "html") {
            let url = URL(fileURLWithPath: filePath, isDirectory: false)
            return URLRequest(url: url)
        }
        
        return nil
    }

    public static var secondPersonSetupURLRequest: URLRequest? {
        
        if let filePath = Bundle.module.path(forResource: "rich_editor_second_person", ofType: "html") {
            let url = URL(fileURLWithPath: filePath, isDirectory: false)
            return URLRequest(url: url)
        }
        
        return nil
    }
}
