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
    
    static var scalesPageToFitJS: String {
        """
            var meta = document.createElement('meta');
            meta.setAttribute('name', 'viewport');
            meta.setAttribute('content', 'width=device-width');
            document.getElementsByTagName('head')[0].appendChild(meta);
        """
    }
    
    static func scalePages(by constantFactor: CGFloat) -> String {

        let constantFactorRounded = String(format: "%.1f", constantFactor)
        return """
            var meta = document.createElement('meta');
                        meta.setAttribute('name', 'viewport');
                        meta.setAttribute('content', 'width=device-width, initial-scale=\(constantFactorRounded), shrink-to-fit=no');
                        document.getElementsByTagName('head')[0].appendChild(meta);
            """
    }
    
    func scalesPageToFit() {
        
        let javaScript = WKWebView.scalesPageToFitJS
        self.evaluateJavaScript(javaScript)
    }
    
    func scalePages(by constantFactor: CGFloat) {
        
        let javaScript = WKWebView.scalePages(by: constantFactor)
        self.evaluateJavaScript(javaScript)
    }
}

extension WKUserContentController {
    
    convenience init(javaScript: String) {
        
        self.init()
        let userScript = WKUserScript(source: javaScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        addUserScript(userScript)
    }
}









//class YourController: UIViewController {
//
//    @IBOutlet weak var webView: PWebView!
//    var toolbar : UIToolbar?
//
//    func viewDidLoad() {
//        webView.addInputAccessoryView(toolbar: self.getToolbar(height: 44))
//    }
//
//    func getToolbar(height: Int) -> UIToolbar? {
//        let toolBar = UIToolbar()
//        toolBar.frame = CGRect(x: 0, y: 50, width: 320, height: height)
//        toolBar.barStyle = .black
//        toolBar.tintColor = .white
//        toolBar.barTintColor = UIColor.blue
//
//        let doneButton = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(onToolbarDoneClick(sender:)))
//        let flexibleSpaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil )
//
//        toolBar.setItems([flexibleSpaceItem, doneButton], animated: false)
//        toolBar.isUserInteractionEnabled = true
//
//        toolBar.sizeToFit()
//        return toolBar
//    }
//
//    @objc func onToolbarDoneClick(sender: UIBarButtonItem) {
//        webView?.resignFirstResponder()
//    }
//}


var ToolbarHandle: UInt8 = 0

public extension WKWebView {
    
    func addInputAccessoryView(toolbar: UIView?) {
        guard let toolbar = toolbar else {return}
        objc_setAssociatedObject(self, &ToolbarHandle, toolbar, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        var candidateView: UIView? = nil
        for view in self.scrollView.subviews {
            let description : String = String(describing: type(of: view))
            if description.hasPrefix("WKContent") {
                candidateView = view
                break
            }
        }
        guard let targetView = candidateView else {return}
        let newClass: AnyClass? = classWithCustomAccessoryView(targetView: targetView)

        guard let targetNewClass = newClass else {return}

        object_setClass(targetView, targetNewClass)
    }

    func classWithCustomAccessoryView(targetView: UIView) -> AnyClass? {
        guard let _ = targetView.superclass else {return nil}
        let customInputAccesoryViewClassName = "_CustomInputAccessoryView"

        var newClass: AnyClass? = NSClassFromString(customInputAccesoryViewClassName)
        if newClass == nil {
            newClass = objc_allocateClassPair(object_getClass(targetView), customInputAccesoryViewClassName, 0)
        } else {
            return newClass
        }

        let newMethod = class_getInstanceMethod(WKWebView.self, #selector(WKWebView.getCustomInputAccessoryView))
        class_addMethod(newClass.self, #selector(getter: WKWebView.inputAccessoryView), method_getImplementation(newMethod!), method_getTypeEncoding(newMethod!))

        objc_registerClassPair(newClass!)

        return newClass
    }

    @objc func getCustomInputAccessoryView() -> UIView? {
        var superWebView: UIView? = self
        while (superWebView != nil) && !(superWebView is WKWebView) {
            superWebView = superWebView?.superview
        }

        guard let webView = superWebView else {return nil}

        let customInputAccessory = objc_getAssociatedObject(webView, &ToolbarHandle)
        return customInputAccessory as? UIView
    }
}
