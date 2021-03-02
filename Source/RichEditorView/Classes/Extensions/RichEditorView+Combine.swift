//
//  RichEditorView+Combine.swift
//  
//
//  Created by Aswath Narayanan on 02/02/21.
//

import Foundation
import Combine

enum RichEditorViewCombineError: Error {
    case resultNil
}
extension RichEditorView {
    
    //MARK: WARNING METHOD CAUSES CRASHES; ZERO IDEA WHY
//    func runJSFuture(_ js: String) -> Future<Any?, Error> {
//
//        Future<Any?, Error> { promise in
//            self.runJS(js) { (result, error) in
//
//                if let errorUnwrapped = error {
//
//                    promise(.failure(errorUnwrapped))
//                    return
//                }
//
//                promise(.success(result))
//            }
//        }
//    }
    
    func runJSFuture(_ js: String) -> AnyPublisher<Any?, Error> {
        
        let pts = PassthroughSubject<Any?, Error>()
        
        self.runJS(js) { (result, error) in
            
            if let errorUnwrapped = error {
                
                pts.send(completion: .failure(errorUnwrapped))
                return
            }
            
            pts.send(result)
//            pts.send(completion: .finished)
            //MARK: crashes if the line above is executed sometimes; but this is a terrible idea. if the above line is commented, the pipeline will never complete
        }
        
        return pts.eraseToAnyPublisher()
    }
    
    func runJSSilently(_ js: String) {
        
        runJS(js) { (_, _) in }
    }
}

