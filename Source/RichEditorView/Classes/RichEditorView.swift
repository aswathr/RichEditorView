//
//  RichEditor.swift
//
//  Created by Caesar Wirth on 4/1/15.
//  Copyright (c) 2015 Caesar Wirth. All rights reserved.
//

import UIKit
import RichEditorView_ObjC
import WebKit
import Combine

/// RichEditorDelegate defines callbacks for the delegate of the RichEditorView
@objc public protocol RichEditorDelegate: class {

    /// Called when the inner height of the text being displayed changes
    /// Can be used to update the UI
    @objc optional func richEditor(_ editor: RichEditorView, heightDidChange height: Int)

    /// Called whenever the content inside the view changes
    @objc optional func richEditor(_ editor: RichEditorView, contentDidChange content: String)

    /// Called when the rich editor starts editing
    @objc optional func richEditorTookFocus(_ editor: RichEditorView)
    
    /// Called when the rich editor stops editing or loses focus
    @objc optional func richEditorLostFocus(_ editor: RichEditorView)
    
    /// Called when the RichEditorView has become ready to receive input
    /// More concretely, is called when the internal WKWebView loads for the first time, and contentHTML is set
    @objc optional func richEditorDidLoad(_ editor: RichEditorView)
    
    /// Called when the internal WKWebView begins loading a URL that it does not know how to respond to
    /// For example, if there is an external link, and then the user taps it
    @objc optional func richEditor(_ editor: RichEditorView, shouldInteractWith url: URL) -> Bool
    
    /// Called when custom actions are called by callbacks in the JS
    /// By default, this method is not used unless called by some custom JS that you add
    @objc optional func richEditor(_ editor: RichEditorView, handle action: String)
}

/// RichEditorView is a UIView that displays richly styled text, and allows it to be edited in a WYSIWYG fashion.
@objcMembers open class RichEditorView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    var anyCancellables = Set<AnyCancellable>()
    
    // MARK: Public Properties

    /// The delegate that will receive callbacks when certain actions are completed.
    open weak var delegate: RichEditorDelegate?

//    /// Input accessory view to display over they keyboard.
//    /// Defaults to nil
//    open override var inputAccessoryView: UIView? {
//        get { return webView.inputAccessoryView }
//        set { webView.inputAccessoryView = newValue }
//    }
    
    open override var inputAccessoryView: UIView? {
        get {
            
            webView.getCustomInputAccessoryView()
        } set {
            
            webView.addInputAccessoryView(toolbar: newValue)
        }
    }

    /// The internal WKWebView that is used to display the text.
    open private(set) var webView: WKWebView

    /// Whether or not scroll is enabled on the view.
    open var isScrollEnabled: Bool = true {
        didSet {
            webView.scrollView.isScrollEnabled = isScrollEnabled
        }
    }

    /// Whether or not to allow user input in the view.
    
    open var fetchIsEditingEnabled: AnyPublisher<Bool, Error> {
        fetchIsContentEditable
    }
    
    open func setIsEditingEnabled(_ newValue: Bool) {
        setIsContentEditable(newValue)
    }

    /// The content HTML of the text being displayed.
    /// Is continually updated as the text is being edited.
    open private(set) var contentHTML: String = "" {
        didSet {
            delegate?.richEditor?(self, contentDidChange: contentHTML)
        }
    }

    /// The internal height of the text being displayed.
    /// Is continually being updated as the text is edited.
    open private(set) var editorHeight: Int = 0 {
        didSet {
            delegate?.richEditor?(self, heightDidChange: editorHeight)
        }
    }

    /// The value we hold in order to be able to set the line height before the JS completely loads.
    private var innerLineHeight: Int = 28

    /// The line height of the editor. Defaults to 28.
    public var fetchLineHeight: AnyPublisher<Int, Error> {
        
            if self.isEditorLoaded {
                
                return self.runJSFuture("RE.getLineHeight();")
                    .map { $0 as? String }
                    .map { Int($0 ?? "") }
                    .map { $0 ?? self.innerLineHeight }
                    .eraseToAnyPublisher()
            } else {
                
                return Just(innerLineHeight)
                    .mapError { _ in REError.genericREError }
                    .eraseToAnyPublisher()
            }
    }
    
    public func setLineHeight(_ newLineHeight: Int) {
        
        innerLineHeight = newLineHeight
        runJSSilently("RE.setLineHeight('\(innerLineHeight)px');")
    }

    // MARK: Private Properties

    /// Whether or not the editor has finished loading or not yet.
    private var isEditorLoaded = false

    /// Value that stores whether or not the content should be editable when the editor is loaded.
    /// Is basically `isEditingEnabled` before the editor is loaded.
    private var editingEnabledVar = true

    /// The private internal tap gesture recognizer used to detect taps and focus the editor
    private let tapRecognizer = UITapGestureRecognizer()

    /// The inner height of the editor div.
    /// Fetches it from JS every time, so might be slow!
    private var fetchClientHeight: AnyPublisher<Int, Error> {
        runJSFuture("document.getElementById('editor').clientHeight;")
            .map { $0 as? String }
            .map { Int($0 ?? "") }
            .map { $0 ?? 0 }
            .eraseToAnyPublisher()
    }
    
    // MARK: Initialization
    
    public override init(frame: CGRect) {
        
        webView = WKWebView(frame: frame, configuration: RichEditorView.wkWebViewConfiguration)
        super.init(frame: frame)
        setup()
    }

    required public init?(coder aDecoder: NSCoder) {
        webView = WKWebView()
        super.init(coder: aDecoder)
        setup()
    }
    
    private static var wkWebViewConfiguration: WKWebViewConfiguration = {
        
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = WKDataDetectorTypes()
        
        return configuration
    }()
    
    private func setup() {
        backgroundColor = .red
        
        webView.frame = bounds
        webView.navigationDelegate = self
        webView.setKeyboardRequiresUserInteraction(false)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.backgroundColor = .white
        
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = false
        webView.scrollView.delegate = self
        webView.scrollView.clipsToBounds = false
        
        webView.cjw_inputAccessoryView = nil
        
        self.addSubview(webView)
        
        if let filePath = Bundle.module.path(forResource: "rich_editor", ofType: "html") {
            let url = URL(fileURLWithPath: filePath, isDirectory: false)
            let request = URLRequest(url: url)
            webView.load(request)
        }

        tapRecognizer.addTarget(self, action: #selector(viewWasTapped))
        tapRecognizer.delegate = self
        addGestureRecognizer(tapRecognizer)
    }

    // MARK: - Rich Text Editing

    // MARK: Properties

    /// The HTML that is currently loaded in the editor view, if it is loaded. If it has not been loaded yet, it is the
    /// HTML that will be loaded into the editor view once it finishes initializing.
    public var fetchHTML: AnyPublisher<String, Error> {
        runJSFuture("RE.getHtml();")
            .map { $0 as? String }
            .map { $0 ?? "" }
            .eraseToAnyPublisher()
    }
    
    public func setHTML(_ newValue: String) {
        
        contentHTML = newValue
        if isEditorLoaded {
            runJSSilently("RE.setHtml('\(newValue.escaped)');")
            updateHeight()
        }
    }

    /// Text representation of the data that has been input into the editor view, if it has been loaded.
    public var fetchText: AnyPublisher<String, Error> {
        runJSFuture("RE.getText()")
            .map { $0 as? String }
            .map { $0 ?? "" }
            .eraseToAnyPublisher()
    }

    /// Private variable that holds the placeholder text, so you can set the placeholder before the editor loads.
    private var placeholderText: String = ""
    /// The placeholder text that should be shown when there is no user input.
    open var placeholder: String {
        get { return placeholderText }
        set {
            placeholderText = newValue
            runJSSilently("RE.setPlaceholderText('\(newValue.escaped)');")
        }
    }


    /// The href of the current selection, if the current selection's parent is an anchor tag.
    /// Will be nil if there is no href, or it is an empty string.
    public var fetchSelectedHref: AnyPublisher<String?, Error> {
        
        fetchHasRangeSelection
            .flatMap { hasRangeSelection -> AnyPublisher<String?, Error> in
                if !hasRangeSelection {
                    return Just(nil)
                        .mapError { _ in REError.genericREError }
                        .eraseToAnyPublisher()
                }
                
                return self.runJSFuture("RE.getSelectedHref();")
                    .map { $0 as? String }
                    .map { $0 ?? "" }
                    .map { href -> String? in
                        
                        if href == "" {
                            return nil
                        } else {
                            return href
                        }
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    /// Whether or not the selection has a type specifically of "Range".
    public var fetchHasRangeSelection: AnyPublisher<Bool, Error> {
        
        runJSFuture("RE.rangeSelectionExists();")
            .map { $0 as? String }
            .map { $0 ?? "false" }
            .map {$0 == "true" ? true : false }
            .eraseToAnyPublisher()
    }

    /// Whether or not the selection has a type specifically of "Range" or "Caret".
    public var fetchHasRangeOrCaretSelection: AnyPublisher<Bool, Error> {
        
        runJSFuture("RE.rangeSelectionExists();")
            .map { $0 as? String }
            .map { $0 ?? "false" }
            .map {$0 == "true" ? true : false }
            .eraseToAnyPublisher()
    }

    // MARK: Methods

    public func removeFormat() {
        runJSSilently("RE.removeFormat();")
    }
    
    public func setFontSize(_ size: Int) {
        runJSSilently("RE.setFontSize('\(size)px');")
    }
    
    public func setEditorBackgroundColor(_ color: UIColor) {
        runJSSilently("RE.setBackgroundColor('\(color.hex)');")
    }
    
    public func undo() {
        runJSSilently("RE.undo();")
    }
    
    public func redo() {
        runJSSilently("RE.redo();")
    }
    
    public func bold() {
        runJSSilently("RE.setBold();")
    }
    
    public func italic() {
        runJSSilently("RE.setItalic();")
    }
    
    // "superscript" is a keyword
    public func subscriptText() {
        runJSSilently("RE.setSubscript();")
    }
    
    public func superscript() {
        runJSSilently("RE.setSuperscript();")
    }
    
    public func strikethrough() {
        runJSSilently("RE.setStrikeThrough();")
    }
    
    public func underline() {
        runJSSilently("RE.setUnderline();")
    }
    
    public func setTextColor(_ color: UIColor) {
        runJSSilently("RE.prepareInsert();")
        runJSSilently("RE.setTextColor('\(color.hex)');")
    }
    
    public func setEditorFontColor(_ color: UIColor) {
        runJSSilently("RE.setBaseTextColor('\(color.hex)');")
    }
    
    public func setTextBackgroundColor(_ color: UIColor) {
        runJSSilently("RE.prepareInsert();")
        runJSSilently("RE.setTextBackgroundColor('\(color.hex)');")
    }
    
    public func header(_ h: Int) {
        runJSSilently("RE.setHeading('\(h)');")
    }

    public func indent() {
        runJSSilently("RE.setIndent();")
    }

    public func outdent() {
        runJSSilently("RE.setOutdent();")
    }

    public func orderedList() {
        runJSSilently("RE.setOrderedList();")
    }

    public func unorderedList() {
        runJSSilently("RE.setUnorderedList();")
    }

    public func blockquote() {
        runJSSilently("RE.setBlockquote()");
    }
    
    public func alignLeft() {
        runJSSilently("RE.setJustifyLeft();")
    }
    
    public func alignCenter() {
        runJSSilently("RE.setJustifyCenter();")
    }
    
    public func alignRight() {
        runJSSilently("RE.setJustifyRight();")
    }
    
    public func insertImage(_ url: String, alt: String) {
        runJSSilently("RE.prepareInsert();")
        runJSSilently("RE.insertImage('\(url.escaped)', '\(alt.escaped)');")
    }
    
    public func insertLink(_ href: String, title: String) {
        runJSSilently("RE.prepareInsert();")
        runJSSilently("RE.insertLink('\(href.escaped)', '\(title.escaped)');")
    }
    
    public func focus() {
        runJSSilently("RE.focus();")
    }

    public func focus(at: CGPoint) {
        runJSSilently("RE.focusAtPoint(\(at.x), \(at.y));")
    }
    
    public func blur() {
        runJSSilently("RE.blurFocus()")
    }
/*
    /// Runs some JavaScript on the WKWebView and returns the result
    /// If there is no result, returns an empty string
    /// - parameter js: The JavaScript string to be run
    /// - returns: The result of the JavaScript that was run
    @discardableResult
    public func runJS(_ js: String) -> String {
        let string = webView.stringByEvaluatingJavaScript(from: js) ?? ""
        return string
    }
*/
    
    public func runJS(_ js: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        webView.evaluateJavaScript(js, completionHandler: completionHandler)
    }


    // MARK: - Delegate Methods


    // MARK: UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // We use this to keep the scroll view from changing its offset when the keyboard comes up
        if !isScrollEnabled {
            scrollView.bounds = webView.bounds
        }
    }

    // MARK: UIGestureRecognizerDelegate

    /// Delegate method for our UITapGestureDelegate.
    /// Since the internal web view also has gesture recognizers, we have to make sure that we actually receive our taps.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }


    // MARK: - Private Implementation Details
    
    private var fetchIsContentEditable: AnyPublisher<Bool, Error> {
        
        if isEditorLoaded {
            
            return runJSFuture("RE.editor.isContentEditable")
                .map { $0 as? Bool }
                .map { $0 ?? false }
                .handleEvents(receiveOutput: {
                    self.editingEnabledVar = $0
                })
                .eraseToAnyPublisher()
        } else {
            
            return Just(editingEnabledVar)
                .mapError { _ in REError.genericREError }
                .eraseToAnyPublisher()
        }
    }
    
    private func setIsContentEditable(_ newValue: Bool) {
        
        editingEnabledVar = newValue
        if isEditorLoaded {
            let value = newValue ? "true" : "false"
            runJSSilently("RE.editor.contentEditable = \(value);")
        }

    }
    
    /// The position of the caret relative to the currently shown content.
    /// For example, if the cursor is directly at the top of what is visible, it will return 0.
    /// This also means that it will be negative if it is above what is currently visible.
    /// Can also return 0 if some sort of error occurs between JS and here.
    private var fetchRelativeCaretYPosition: AnyPublisher<Int, Error> {
        return self.runJSFuture("RE.getRelativeCaretYPosition();")
            .map { $0 as? String }
            .map { Int($0 ?? "") }
            .map { $0 ?? 0 }
            .eraseToAnyPublisher()

    }
    
    private func updateHeight() {
        
        runJSFuture("document.getElementById('editor').clientHeight;")
            .map { $0 as? String }
            .map { Int($0 ?? "") }
            .map { $0 ?? 0 }
            .handleEvents(receiveOutput: {
                
                if self.editorHeight != $0 {
                    self.editorHeight = $0
                }
            })
            .sink { _ in } receiveValue: { _ in }
            .store(in: &anyCancellables)
    }

    /// Scrolls the editor to a position where the caret is visible.
    /// Called repeatedly to make sure the caret is always visible when inputting text.
    /// Works only if the `lineHeight` of the editor is available.
    private func scrollCaretToVisible() {
        let scrollView = self.webView.scrollView
        
        fetchClientHeight.handleEvents(receiveOutput: { clientHeightInt in
            
            let contentHeight = clientHeightInt > 0 ? CGFloat(clientHeightInt) : scrollView.frame.height
            scrollView.contentSize = CGSize(width: scrollView.frame.width, height: contentHeight)
        })
        .sink { _ in } receiveValue: { _ in }
        .store(in: &anyCancellables)
        
        fetchLineHeight.combineLatest(fetchRelativeCaretYPosition)
            .handleEvents(receiveOutput: { (lineHeightInt, relativeCaretYPositionInt) in
                // XXX: Maybe find a better way to get the cursor height
                let lineHeight = CGFloat(lineHeightInt)
                let cursorHeight = lineHeight - 4
                let visiblePosition = CGFloat(relativeCaretYPositionInt)
                var offset: CGPoint?

                if visiblePosition + cursorHeight > scrollView.bounds.size.height {
                    // Visible caret position goes further than our bounds
                    offset = CGPoint(x: 0, y: (visiblePosition + lineHeight) - scrollView.bounds.height + scrollView.contentOffset.y)

                } else if visiblePosition < 0 {
                    // Visible caret position is above what is currently visible
                    var amount = scrollView.contentOffset.y + visiblePosition
                    amount = amount < 0 ? 0 : amount
                    offset = CGPoint(x: scrollView.contentOffset.x, y: amount)

                }

                if let offset = offset {
                    scrollView.setContentOffset(offset, animated: true)
                }
            })
            .sink { _ in } receiveValue: { _ in }
            .store(in: &anyCancellables)
    }
    
    /// Called when actions are received from JavaScript
    /// - parameter method: String with the name of the method and optional parameters that were passed in
    private func performCommand(_ method: String) {
        if method.hasPrefix("ready") {
            // If loading for the first time, we have to set the content HTML to be displayed
            if !isEditorLoaded {
                isEditorLoaded = true
                setHTML(contentHTML)
                setIsContentEditable(editingEnabledVar)
                placeholder = placeholderText
                setLineHeight(innerLineHeight)
                delegate?.richEditorDidLoad?(self)
            }
            updateHeight()
        }
        else if method.hasPrefix("input") {
            scrollCaretToVisible()
            runJSFuture("RE.getHtml()")
                .map { $0 as? String }
                .map { $0 ?? "" }
                .handleEvents(receiveOutput: {
                    self.contentHTML = $0
                })
                .sink { _ in } receiveValue: { _ in }
                .store(in: &anyCancellables)
            updateHeight()
        }
        else if method.hasPrefix("updateHeight") {
            updateHeight()
        }
        else if method.hasPrefix("focus") {
            delegate?.richEditorTookFocus?(self)
        }
        else if method.hasPrefix("blur") {
            delegate?.richEditorLostFocus?(self)
        }
        else if method.hasPrefix("action/") {
            runJSFuture("RE.getHtml()")
                .map { $0 as? String }
                .map { $0 ?? "" }
                .handleEvents(receiveOutput: { content in
                    self.contentHTML = content
                    
                    // If there are any custom actions being called
                    // We need to tell the delegate about it
                    let actionPrefix = "action/"
                    let range = method.range(of: actionPrefix)!
                    let action = method.replacingCharacters(in: range, with: "")
                    self.delegate?.richEditor?(self, handle: action)

                })
                .sink { _ in } receiveValue: { _ in }
                .store(in: &anyCancellables)
        }
    }

    // MARK: - Responder Handling

    /// Called by the UITapGestureRecognizer when the user taps the view.
    /// If we are not already the first responder, focus the editor.
    @objc private func viewWasTapped() {
        if !webView.containsFirstResponder {
            let point = tapRecognizer.location(in: webView)
            focus(at: point)
        }
    }

    override open func becomeFirstResponder() -> Bool {
        if !webView.containsFirstResponder {
            focus()
            return true
        } else {
            return false
        }
    }

    open override func resignFirstResponder() -> Bool {
        blur()
        return true
    }

}

//extension RichEditorView: UIWebViewDelegate {
//
//    // MARK: UIWebViewDelegate
//
//    public func webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebViewNavigationType) -> Bool {
//
//        // Handle pre-defined editor actions
//        let callbackPrefix = "re-callback://"
//        if request.url?.absoluteString.hasPrefix(callbackPrefix) == true {
//
//            // When we get a callback, we need to fetch the command queue to run the commands
//            // It comes in as a JSON array of commands that we need to parse
//            let commands = runJS("RE.getCommandQueue();")
//
//            if let data = commands.data(using: .utf8) {
//
//                let jsonCommands: [String]
//                do {
//                    jsonCommands = try JSONSerialization.jsonObject(with: data) as? [String] ?? []
//                } catch {
//                    jsonCommands = []
//                    NSLog("RichEditorView: Failed to parse JSON Commands")
//                }
//
//                jsonCommands.forEach(performCommand)
//            }
//
//            return false
//        }
//
//        // User is tapping on a link, so we should react accordingly
//        if navigationType == .linkClicked {
//            if let
//                url = request.url,
//                let shouldInteract = delegate?.richEditor?(self, shouldInteractWith: url)
//            {
//                return shouldInteract
//            }
//        }
//
//        return true
//    }
//}

extension RichEditorView: WKNavigationDelegate {
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        let navigationType = navigationAction.navigationType
        let request = navigationAction.request
        
        // Handle pre-defined editor actions
        let callbackPrefix = "re-callback://"
        if request.url?.absoluteString.hasPrefix(callbackPrefix) == true {
            
            // When we get a callback, we need to fetch the command queue to run the commands
            // It comes in as a JSON array of commands that we need to parse
            runJSFuture("RE.getCommandQueue();")
                .map { $0 as? String }
                .map { $0 ?? "" }
                .handleEvents(receiveOutput: { commands in
                    
                    if let data = commands.data(using: .utf8) {
                        
                        let jsonCommands: [String]
                        do {
                            jsonCommands = try JSONSerialization.jsonObject(with: data) as? [String] ?? []
                        } catch {
                            jsonCommands = []
                            NSLog("RichEditorView: Failed to parse JSON Commands")
                        }
                        
                        jsonCommands.forEach(self.performCommand)
                    }
                    decisionHandler(.cancel)
                })
                .sink { _ in } receiveValue: { _ in }
                .store(in: &anyCancellables)
            return
        }
        
        // User is tapping on a link, so we should react accordingly
        if navigationType == .linkActivated {
            if let
                url = request.url,
                let shouldInteract = delegate?.richEditor?(self, shouldInteractWith: url)
            {
                decisionHandler(shouldInteract ? .allow : .cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
}
