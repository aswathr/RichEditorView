//
//  RichEditorView+Combine.swift
//  
//
//  Created by Aswath Narayanan on 02/02/21.
//

import Foundation
import Combine

extension RichEditorView {
    
    func runJSFuture(_ js: String) -> Future<Any?, Error> {
        
        Future<Any?, Error> { promise in
            self.runJS(js) { (result, error) in
                
                if let errorUnwrapped = error {
                    
                    promise(.failure(errorUnwrapped))
                    return
                }
                
                promise(.success(result))
            }
        }
    }
    
    func runJSSilently(_ js: String) {
        
        runJS(js) { (_, _) in }
    }
}
