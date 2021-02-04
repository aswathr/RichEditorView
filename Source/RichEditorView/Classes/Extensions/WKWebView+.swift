//
//  WKWebView+.swift
//  
//
//  Created by Aswath Narayanan on 01/02/21.
//  NOTE: Inspired from https://stackoverflow.com/questions/32449870/programmatically-focus-on-a-form-in-a-webview-wkwebview

import WebKit

typealias OldClosureType =  @convention(c) (Any, Selector, UnsafeRawPointer, Bool, Bool, Any?) -> Void
typealias NewClosureType =  @convention(c) (Any, Selector, UnsafeRawPointer, Bool, Bool, Bool, Any?) -> Void


extension WKWebView {
    
    func setKeyboardRequiresUserInteraction( _ value: Bool) {
        
        guard
            let wkc: AnyClass = NSClassFromString("WKContentView") else {
            print("Cannot find the WKContentView class")
            return
        }
        
        let v1Selector: Selector = sel_getUid("_startAssistingNode:userIsInteracting:blurPreviousNode:userObject:")
        let v2Selector: Selector = sel_getUid("_startAssistingNode:userIsInteracting:blurPreviousNode:changingActivityState:userObject:")
        let v3Selector: Selector = sel_getUid("_elementDidFocus:userIsInteracting:blurPreviousNode:changingActivityState:userObject:")
        let v4Selector: Selector = sel_getUid("_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:")
        
        if let method = class_getInstanceMethod(wkc, v1Selector) {
            
            let originalImp: IMP = method_getImplementation(method)
            let original: OldClosureType = unsafeBitCast(originalImp, to: OldClosureType.self)
            let block : @convention(block) (Any, UnsafeRawPointer, Bool, Bool, Any?) -> Void = { (me, arg0, arg1, arg2, arg3) in
                original(me, v1Selector, arg0, !value, arg2, arg3)
            }
            let imp: IMP = imp_implementationWithBlock(block)
            method_setImplementation(method, imp)
        }
        
        if let method = class_getInstanceMethod(wkc, v2Selector) {
            self.swizzleAutofocusMethod(method, v2Selector, value)
        }
        
        if let method = class_getInstanceMethod(wkc, v3Selector) {
            self.swizzleAutofocusMethod(method, v3Selector, value)
        }
        
        if let method = class_getInstanceMethod(wkc, v4Selector) {
            self.swizzleAutofocusMethod(method, v4Selector, value)
        }
    }
    
    func swizzleAutofocusMethod(_ method: Method, _ selector: Selector, _ value: Bool) {
        let originalImp: IMP = method_getImplementation(method)
        let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
        let block : @convention(block) (Any, UnsafeRawPointer, Bool, Bool, Bool, Any?) -> Void = { (me, arg0, arg1, arg2, arg3, arg4) in
            original(me, selector, arg0, !value, arg2, arg3, arg4)
        }
        let imp: IMP = imp_implementationWithBlock(block)
        method_setImplementation(method, imp)
    }
    
    func scalesPageToFit() {
        
        let javaScript = """
            var meta = document.createElement('meta');
                        meta.setAttribute('name', 'viewport');
                        meta.setAttribute('content', 'width=device-width');
                        document.getElementsByTagName('head')[0].appendChild(meta);
            """

        self.evaluateJavaScript(javaScript)
    }
}
