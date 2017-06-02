/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
import SnapKit
import XCGLogger

private let log = Logger.browserLogger



//static struct. causes long compile times when you change a small thing. Why?
struct URLBarViewUX {
    //clean up
    static let LocationLeftPadding = 6
    static let LocationHeight = 28
    static let LocationContentOffset: CGFloat = 10
    static let ProgressTintColor = UIColor(rgb: 0x00A2FE)
    static let TabsButtonRotationOffset: CGFloat = 1.5
    static let TabsButtonHeight: CGFloat = 18.0
    static let ToolbarButtonInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

    static let Themes: [String: Theme] = {
        var themes = [String: Theme]()
        var theme = Theme()
        theme.tintColor = UIConstants.PrivateModePurple
        theme.textColor = UIColor.white
        theme.backgroundColor = UIConstants.PrivateModeLocationBorderColor
        theme.buttonTintColor = UIConstants.PrivateModeActionButtonTintColor
        theme.seperatorColor = UIColor(rgb: 0x3d3d3d)

        themes[Theme.PrivateMode] = theme

        theme = Theme()
        theme.backgroundColor = UIColor(rgb: 0xf7fafc)
        theme.tintColor = ProgressTintColor
        theme.textColor = UIColor(rgb: 0x272727)
        theme.buttonTintColor = UIColor.darkGray
        theme.seperatorColor = UIColor(rgb: 0xe4e4e4)
        themes[Theme.NormalMode] = theme

        return themes
    }()

    static func backgroundColorWithAlpha(_ alpha: CGFloat) -> UIColor {
        return UIColor(rgb: 0xF7FAFC).withAlphaComponent(alpha)
    }
}

// Used by BrowserVC to show the correct view controllers and set the right browser state
protocol URLBarDelegate: class {
    func urlBarDidPressTabs(_ urlBar: URLBarView)
    func urlBarDidPressReaderMode(_ urlBar: URLBarView)

    /// - returns: whether the long-press was handled by the delegate; i.e. return `false` when the conditions for even starting handling long-press were not satisfied
    func urlBarDidLongPressReaderMode(_ urlBar: URLBarView) -> Bool
    func urlBarDidEnterOverlayMode(_ urlBar: URLBarView)
    func urlBarDidLeaveOverlayMode(_ urlBar: URLBarView)
    func urlBarDidLongPressLocation(_ urlBar: URLBarView)
    func urlBarLocationAccessibilityActions(_ urlBar: URLBarView) -> [UIAccessibilityCustomAction]?
    func urlBarDidPressScrollToTop(_ urlBar: URLBarView)
    func urlBar(_ urlBar: URLBarView, didEnterText text: String)
    func urlBar(_ urlBar: URLBarView, didSubmitText text: String)
    func urlBarDisplayTextForURL(_ url: URL?) -> String?
}


/*
 the state of the urlBar
 // isTransitioning
 // toolbarIsshowing
 // toptabsisshowing
 // inOverlayMode
 // url
 // setShowToolbar
 // updateAlphaForSubviews
 // updateTabCount
 // updateProgressBar
 // updateReaderModeState
 // setAutocompleteSuggestion
 // enterOverlayMode
 */

extension UIView {

    func addSubviews(views: UIView...) {
        views.forEach { self.addSubview($0) }
    }
}



class URLBarView: UIView {
    weak var delegate: URLBarDelegate? // A BrowserVC
    weak var tabToolbarDelegate: TabToolbarDelegate?
    var helper: TabToolbarHelper? // When the device is rotated. The urlbar includes icons that would normally be in the bottom toolbar
    // this abstracts the changes out

    // used to reset progress bar and say if we should animate or not
    var isTransitioning: Bool = false {
        didSet {
            if isTransitioning {
                // Cancel any pending/in-progress animations related to the progress bar
                self.progressBar.setProgress(1, animated: false)
                self.progressBar.alpha = 0.0
            }
        }
    }


    var toolbarIsShowing = false
    var topTabsIsShowing = false

    fileprivate var locationTextField: ToolbarTextField?

    /// Overlay mode is the state where the lock/reader icons are hidden, the home panels are shown,
    /// and the Cancel button is visible (allowing the user to leave overlay mode). Overlay mode
    /// is *not* tied to the location text field's editing state; for instance, when selecting
    /// a panel, the first responder will be resigned, yet the overlay mode UI is still active.
    var inOverlayMode = false


    //V I E W S
    lazy var locationView: TabLocationView = {
        let locationView = TabLocationView()
        locationView.translatesAutoresizingMaskIntoConstraints = false
        locationView.readerModeState = ReaderModeState.unavailable
        locationView.delegate = self
        locationView.backgroundColor = .red
        return locationView
    }()

    lazy var locationContainer: UIView = {
        let locationContainer = UIView()
        locationContainer.translatesAutoresizingMaskIntoConstraints = false
        locationContainer.backgroundColor = self.backgroundColor
        locationContainer.backgroundColor = UIColor(rgb: 0xF7FAFC)
        return locationContainer
    }()

    fileprivate lazy var tabsButton: TabsButton = {
        let tabsButton = TabsButton.tabTrayButton()
        tabsButton.addTarget(self, action: #selector(URLBarView.SELdidClickAddTab), for: .touchUpInside)
        tabsButton.accessibilityIdentifier = "URLBarView.tabsButton"

        return tabsButton
    }()

    fileprivate lazy var progressBar: UIProgressView = {
        let progressBar = UIProgressView()
        progressBar.progressTintColor = URLBarViewUX.ProgressTintColor
        progressBar.backgroundColor = .clear
        progressBar.trackTintColor = .clear
        progressBar.alpha = 0
        progressBar.layer.cornerRadius = 1
        progressBar.isHidden = true
        return progressBar
    }()

    fileprivate lazy var cancelButton: UIButton = {
        let cancelButton = InsetButton()
        cancelButton.setTitleColor(UIColor(rgb: 0x272727), for: UIControlState())
        let cancelTitle = NSLocalizedString("Cancel", comment: "Label for Cancel button")
        cancelButton.setTitle(cancelTitle, for: UIControlState())
        cancelButton.titleLabel?.font = UIConstants.DefaultChromeFont
        cancelButton.addTarget(self, action: #selector(URLBarView.SELdidClickCancel), for: .touchUpInside)
        cancelButton.titleEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 14)
        cancelButton.setContentHuggingPriority(1000, for: .horizontal)
        cancelButton.setContentCompressionResistancePriority(1000, for: .horizontal)
        cancelButton.alpha = 0
        return cancelButton
    }()


    fileprivate lazy var scrollToTopButton: UIButton = {
        let button = UIButton()
        button.addTarget(self, action: #selector(URLBarView.SELtappedScrollToTopArea), for: .touchUpInside)
        return button
    }()

    var shareButton: UIButton = ToolbarButton()
    var menuButton: UIButton = ToolbarButton()
    var bookmarkButton: UIButton = ToolbarButton()
    var forwardButton: UIButton = ToolbarButton()
    var stopReloadButton: UIButton = ToolbarButton()

    var homePageButton: UIButton = ToolbarButton()

    var backButton: UIButton = {
        let backButton = ToolbarButton()
        backButton.accessibilityIdentifier = "URLBarView.backButton"
        return backButton
    }()



    lazy var actionButtons: [UIButton] = [self.shareButton, self.menuButton, self.forwardButton, self.backButton, self.stopReloadButton, self.homePageButton]

    var currentURL: URL? {
        get {
            return locationView.url as URL?
        }

        set(newURL) {
            locationView.url = newURL
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    let line = UIView()

    fileprivate func commonInit() {
        backgroundColor = UIColor(rgb: 0xF7FAFC)
        self.addSubviews(views: scrollToTopButton, tabsButton, cancelButton, shareButton, menuButton)
        self.addSubviews(views: homePageButton, forwardButton, backButton, stopReloadButton)

        locationContainer.addSubview(locationView)
        addSubview(locationContainer)


        line.backgroundColor = seperatorColor
        addSubview(line)
        addSubview(progressBar)



        helper = TabToolbarHelper(toolbar: self)
        setupConstraints()
       // locationContainer.backgroundColor = self.backgroundColor
       // locationView.backgroundColor = self.backgroundColor
        // Make sure we hide any views that shouldn't be showing in non-overlay mode.
        updateViewsForOverlayModeAndToolbarChanges()
    }

    private func setupConstraints() {
        line.snp.makeConstraints { make in
            make.bottom.leading.trailing.equalTo(self)
            make.height.equalTo(1)
        }

        scrollToTopButton.snp.makeConstraints { make in
            make.top.equalTo(self)
            make.left.right.equalTo(self.locationContainer)
        }

        progressBar.snp.makeConstraints { make in
            make.top.equalTo(self.snp.bottom).offset(-2)
            make.height.equalTo(3)
            make.width.equalTo(self)
        }

        locationView.snp.makeConstraints { make in
            make.edges.equalTo(self.locationContainer)
        }

        cancelButton.snp.makeConstraints { make in
            make.centerY.equalTo(self.locationContainer)
            make.trailing.equalTo(self)
        }

        tabsButton.snp.makeConstraints { make in
            make.centerY.equalTo(self.locationContainer)
            make.trailing.equalTo(self)
            make.size.equalTo(UIConstants.URLBarHeight)
        }

        backButton.snp.makeConstraints { make in
            make.left.centerY.equalTo(self)
            make.size.equalTo(UIConstants.ToolbarHeight)
        }

        forwardButton.snp.makeConstraints { make in
            make.left.equalTo(self.backButton.snp.right)
            make.centerY.equalTo(self)
            make.size.equalTo(backButton)
        }

        stopReloadButton.snp.makeConstraints { make in
            make.left.equalTo(self.forwardButton.snp.right)
            make.centerY.equalTo(self)
            make.size.equalTo(backButton)
        }

        shareButton.snp.makeConstraints { make in
            make.right.equalTo(self.menuButton.snp.left)
            make.centerY.equalTo(self)
            make.size.equalTo(backButton)
        }

        homePageButton.snp.makeConstraints { make in
            make.center.equalTo(shareButton)
            make.size.equalTo(shareButton)
        }

        menuButton.snp.makeConstraints { make in
            make.right.equalTo(self.tabsButton.snp.left).offset(8)
            make.centerY.equalTo(self)
            make.size.equalTo(backButton)
        }
    }

    override func updateConstraints() {
        super.updateConstraints()
        if inOverlayMode {
            // In overlay mode, we always show the location view full width
            self.locationContainer.snp.remakeConstraints { make in
                make.leading.equalTo(self).offset(URLBarViewUX.LocationLeftPadding)
                make.trailing.equalTo(self.cancelButton.snp.leading)
                //make.width.e
                make.height.equalTo(URLBarViewUX.LocationHeight)
                make.centerY.equalTo(self)
            }
        } else {
            if topTabsIsShowing {
                tabsButton.snp.remakeConstraints { make in
                    make.centerY.equalTo(self.locationContainer)
                    make.leading.equalTo(self.snp.trailing)
                    make.size.equalTo(UIConstants.URLBarHeight)
                }
            } else {
                tabsButton.snp.remakeConstraints { make in
                    make.centerY.equalTo(self.locationContainer)
                    make.trailing.equalTo(self)
                    make.size.equalTo(UIConstants.URLBarHeight)
                }
            }
            self.locationContainer.snp.remakeConstraints { make in
                if self.toolbarIsShowing {
                    // If we are showing a toolbar, show the text field next to the forward button
                    make.leading.equalTo(self.stopReloadButton.snp.trailing)
                    make.trailing.equalTo(self.shareButton.snp.leading)
                } else {
                    // Otherwise, left align the location view
                    make.leading.equalTo(self).offset(URLBarViewUX.LocationLeftPadding)
                    make.trailing.equalTo(self.tabsButton.snp.leading)
                }

                make.height.equalTo(URLBarViewUX.LocationHeight)
                make.centerY.equalTo(self)
            }
        }

    }

    func createLocationTextField() {
        guard locationTextField == nil else { return }

        locationTextField = ToolbarTextField()

        guard let locationTextField = locationTextField else { return }

        locationTextField.translatesAutoresizingMaskIntoConstraints = false
        locationTextField.autocompleteDelegate = self
        locationTextField.keyboardType = UIKeyboardType.webSearch
        locationTextField.autocorrectionType = UITextAutocorrectionType.no
        locationTextField.autocapitalizationType = UITextAutocapitalizationType.none
        locationTextField.returnKeyType = UIReturnKeyType.go
        locationTextField.clearButtonMode = UITextFieldViewMode.whileEditing
        locationTextField.font = UIConstants.DefaultChromeFont
        locationTextField.accessibilityIdentifier = "address"
        locationTextField.accessibilityLabel = NSLocalizedString("Address and Search", comment: "Accessibility label for address and search field, both words (Address, Search) are therefore nouns.")
        locationTextField.backgroundColor = UIColor(rgb: 0xF7FAFC)
        locationTextField.attributedPlaceholder = self.locationView.placeholder

        locationContainer.addSubview(locationTextField)

        locationTextField.snp.makeConstraints { make in
            make.edges.equalTo(self.locationView.urlTextField)
        }

    }

    func removeLocationTextField() {
        locationTextField?.removeFromSuperview()
        locationTextField = nil
    }

    // Ideally we'd split this implementation in two, one URLBarView with a toolbar and one without
    // However, switching views dynamically at runtime is a difficult. For now, we just use one view
    // that can show in either mode.
    func setShowToolbar(_ shouldShow: Bool) {
        toolbarIsShowing = shouldShow
        setNeedsUpdateConstraints()
        // when we transition from portrait to landscape, calling this here causes
        // the constraints to be calculated too early and there are constraint errors
        if !toolbarIsShowing {
            updateConstraintsIfNeeded()
        }
        updateViewsForOverlayModeAndToolbarChanges()
    }

    func updateAlphaForSubviews(_ alpha: CGFloat) {
      //  self.tabsButton.alpha = alpha
       // self.locationContainer.alpha = alpha
      //  self.backgroundColor = URLBarViewUX.backgroundColorWithAlpha(1 - alpha)
        self.locationContainer.backgroundColor = self.backgroundColor
        self.locationView.backgroundColor = self.backgroundColor
        //self.actionButtons.forEach { $0.alpha = alpha }
    }

    func updateTabCount(_ count: Int, animated: Bool = true) {
        self.tabsButton.updateTabCount(count, animated: animated)
    }

    func updateProgressBar(_ progress: Float) {
        if progress == 1.0 {
            self.progressBar.setProgress(progress, animated: !isTransitioning)
            UIView.animate(withDuration: 1.5, animations: {
                self.progressBar.alpha = 0.0
            })
        } else {
            if self.progressBar.alpha < 1.0 {
                self.progressBar.alpha = 1.0
            }
            self.progressBar.setProgress(progress, animated: (progress > progressBar.progress) && !isTransitioning)
        }
    }

    func updateReaderModeState(_ state: ReaderModeState) {
        locationView.readerModeState = state
    }

    func setAutocompleteSuggestion(_ suggestion: String?) {
        locationTextField?.setAutocompleteSuggestion(suggestion)
    }

    func enterOverlayMode(_ locationText: String?, pasted: Bool) {
        createLocationTextField()

        // Show the overlay mode UI, which includes hiding the locationView and replacing it
        // with the editable locationTextField.
        animateToOverlayState(overlayMode: true)

        delegate?.urlBarDidEnterOverlayMode(self)

        // Bug 1193755 Workaround - Calling becomeFirstResponder before the animation happens
        // won't take the initial frame of the label into consideration, which makes the label
        // look squished at the start of the animation and expand to be correct. As a workaround,
        // we becomeFirstResponder as the next event on UI thread, so the animation starts before we
        // set a first responder.
        if pasted {
            // Clear any existing text, focus the field, then set the actual pasted text.
            // This avoids highlighting all of the text.
            self.locationTextField?.text = ""
            DispatchQueue.main.async {
                self.locationTextField?.becomeFirstResponder()
                self.locationTextField?.text = locationText
            }
        } else {
            // Copy the current URL to the editable text field, then activate it.
            self.locationTextField?.text = locationText
            DispatchQueue.main.async {
                self.locationTextField?.becomeFirstResponder()
            }
        }
    }

    func leaveOverlayMode(didCancel cancel: Bool = false) {
        locationTextField?.resignFirstResponder()
        animateToOverlayState(overlayMode: false, didCancel: cancel)
        delegate?.urlBarDidLeaveOverlayMode(self)
    }

    private func prepareOverlayAnimation() {
        // Make sure everything is showing during the transition (we'll hide it afterwards).
        self.bringSubview(toFront: self.locationContainer)
        self.cancelButton.isHidden = false
        self.progressBar.isHidden = false
        let buttons = [self.menuButton, self.forwardButton, self.backButton, self.stopReloadButton, self.homePageButton]
        buttons.forEach { $0.isHidden = !self.toolbarIsShowing }
    }

    private func transitionToOverlay(_ didCancel: Bool = false) {
        self.cancelButton.alpha = inOverlayMode ? 1 : 0
        self.progressBar.alpha = inOverlayMode || didCancel ? 0 : 1
        let buttons = [self.shareButton, self.menuButton, self.forwardButton, self.backButton, self.stopReloadButton, self.homePageButton]
        buttons.forEach { $0.alpha = inOverlayMode ? 0 : 1 }

        if inOverlayMode {
            self.cancelButton.transform = CGAffineTransform.identity
          //  let tabsButtonTransform = CGAffineTransform(translationX: self.tabsButton.frame.width + URLBarViewUX.URLBarCurveOffset, y: 0)
//            self.tabsButton.transform = tabsButtonTransform
         //   self.rightBarConstraint?.update(offset: URLBarViewUX.URLBarCurveOffset + URLBarViewUX.URLBarCurveBounceBuffer + tabsButton.frame.width)

            // Make the editable text field span the entire URL bar, covering the lock and reader icons.
            self.locationTextField?.snp.remakeConstraints { make in
                make.leading.equalTo(self.locationContainer).offset(URLBarViewUX.LocationContentOffset)
                make.top.bottom.trailing.equalTo(self.locationContainer)
            }
        } else {
            self.tabsButton.transform = CGAffineTransform.identity
            self.cancelButton.transform = CGAffineTransform(translationX: self.cancelButton.frame.width, y: 0)
          //  self.rightBarConstraint?.update(offset: defaultRightOffset)

            // Shrink the editable text field back to the size of the location view before hiding it.
            self.locationTextField?.snp.remakeConstraints { make in
                make.edges.equalTo(self.locationView.urlTextField)
            }
        }
    }

    private func updateViewsForOverlayModeAndToolbarChanges() {
        self.cancelButton.isHidden = !inOverlayMode
        self.progressBar.isHidden = inOverlayMode
        let buttons = [self.menuButton, self.forwardButton, self.backButton, self.stopReloadButton]
        buttons.forEach { $0.isHidden = !self.toolbarIsShowing || inOverlayMode }
        self.tabsButton.isHidden = self.topTabsIsShowing
    }

    private func animateToOverlayState(overlayMode overlay: Bool, didCancel cancel: Bool = false) {
        prepareOverlayAnimation()
        layoutIfNeeded()

        inOverlayMode = overlay

        if !overlay {
            removeLocationTextField()
        }

        UIView.animate(withDuration: 0.3, delay: 0.0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.0, options: [], animations: { _ in
            self.transitionToOverlay(cancel)
            self.setNeedsUpdateConstraints()
            self.layoutIfNeeded()
        }, completion: { _ in
            self.updateViewsForOverlayModeAndToolbarChanges()
        })
    }

    func SELdidClickAddTab() {
        delegate?.urlBarDidPressTabs(self)
    }

    func SELdidClickCancel() {
        leaveOverlayMode(didCancel: true)
    }

    func SELtappedScrollToTopArea() {
        delegate?.urlBarDidPressScrollToTop(self)
    }
}

extension URLBarView: TabToolbarProtocol {
    func updateBackStatus(_ canGoBack: Bool) {
        backButton.isEnabled = canGoBack
    }

    func updateForwardStatus(_ canGoForward: Bool) {
        forwardButton.isEnabled = canGoForward
    }

    func updateBookmarkStatus(_ isBookmarked: Bool) {
        bookmarkButton.isSelected = isBookmarked
    }

    func updateReloadStatus(_ isLoading: Bool) {
        helper?.updateReloadStatus(isLoading)
        if isLoading {
            stopReloadButton.setImage(helper?.ImageStop, for: .normal)
            stopReloadButton.setImage(helper?.ImageStopPressed, for: .highlighted)
        } else {
            stopReloadButton.setImage(helper?.ImageReload, for: .normal)
            stopReloadButton.setImage(helper?.ImageReloadPressed, for: .highlighted)
        }
    }

    func updatePageStatus(_ isWebPage: Bool) {
        stopReloadButton.isEnabled = isWebPage
        shareButton.isEnabled = isWebPage
    }

    var access: [Any]? {
        get {
            if inOverlayMode {
                guard let locationTextField = locationTextField else { return nil }
                return [locationTextField, cancelButton]
            } else {
                if toolbarIsShowing {
                    return [backButton, forwardButton, stopReloadButton, locationView, shareButton, menuButton, tabsButton, progressBar]
                } else {
                    return [locationView, tabsButton, progressBar]
                }
            }
        }
        set {
            super.accessibilityElements = newValue
        }
    }
}

extension URLBarView: TabLocationViewDelegate {
    func tabLocationViewDidLongPressReaderMode(_ tabLocationView: TabLocationView) -> Bool {
        return delegate?.urlBarDidLongPressReaderMode(self) ?? false
    }

    func tabLocationViewDidTapLocation(_ tabLocationView: TabLocationView) {
        var locationText = delegate?.urlBarDisplayTextForURL(locationView.url as URL?)

        // Make sure to use the result from urlBarDisplayTextForURL as it is responsible for extracting out search terms when on a search page
        if let text = locationText, let url = URL(string: text), let host = url.host, AppConstants.MOZ_PUNYCODE {
            locationText = url.absoluteString.replacingOccurrences(of: host, with: host.asciiHostToUTF8())
        }
        enterOverlayMode(locationText, pasted: false)
    }

    func tabLocationViewDidLongPressLocation(_ tabLocationView: TabLocationView) {
        delegate?.urlBarDidLongPressLocation(self)
    }

    func tabLocationViewDidTapReaderMode(_ tabLocationView: TabLocationView) {
        delegate?.urlBarDidPressReaderMode(self)
    }

    func tabLocationViewLocationAccessibilityActions(_ tabLocationView: TabLocationView) -> [UIAccessibilityCustomAction]? {
        return delegate?.urlBarLocationAccessibilityActions(self)
    }
}

extension URLBarView: AutocompleteTextFieldDelegate {
    func autocompleteTextFieldShouldReturn(_ autocompleteTextField: AutocompleteTextField) -> Bool {
        guard let text = locationTextField?.text else { return true }
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            delegate?.urlBar(self, didSubmitText: text)
            return true
        } else {
            return false
        }
    }

    func autocompleteTextField(_ autocompleteTextField: AutocompleteTextField, didEnterText text: String) {
        delegate?.urlBar(self, didEnterText: text)
    }

    func autocompleteTextFieldDidBeginEditing(_ autocompleteTextField: AutocompleteTextField) {
        autocompleteTextField.highlightAll()
    }

    func autocompleteTextFieldShouldClear(_ autocompleteTextField: AutocompleteTextField) -> Bool {
        delegate?.urlBar(self, didEnterText: "")
        return true
    }
}

// MARK: UIAppearance
extension URLBarView {
    dynamic var progressBarTint: UIColor? {
        get { return progressBar.progressTintColor }
        set { progressBar.progressTintColor = newValue }
    }

    dynamic var cancelTextColor: UIColor? {
        get { return cancelButton.titleColor(for: UIControlState()) }
        set { return cancelButton.setTitleColor(newValue, for: UIControlState()) }
    }

    dynamic var seperatorColor: UIColor? {
        get { return self.line.backgroundColor }
        set { return self.line.backgroundColor = newValue }
    }

    dynamic var actionButtonTintColor: UIColor? {
        get { return helper?.buttonTintColor }
        set {
            guard let value = newValue else { return }
            helper?.buttonTintColor = value
        }
    }

}

extension URLBarView: Themeable {
    
    func applyTheme(_ themeName: String) {
        locationView.applyTheme(themeName)

        guard let theme = URLBarViewUX.Themes[themeName] else {
            log.error("Unable to apply unknown theme \(themeName)")
            return
        }
        backgroundColor = theme.backgroundColor
        locationTextField?.backgroundColor = backgroundColor
        progressBarTint = theme.tintColor
        cancelTextColor = theme.textColor
        actionButtonTintColor = theme.buttonTintColor
        seperatorColor = theme.seperatorColor

        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.window?.backgroundColor = theme.backgroundColor
        }

        tabsButton.applyTheme(themeName)
    }
}

extension URLBarView: AppStateDelegate {
    func appDidUpdateState(_ appState: AppState) {
        if toolbarIsShowing {
            let showShareButton = HomePageAccessors.isButtonInMenu(appState)
            homePageButton.isHidden = showShareButton
            shareButton.isHidden = !showShareButton || inOverlayMode
            homePageButton.isEnabled = HomePageAccessors.isButtonEnabled(appState)
        } else {
            homePageButton.isHidden = true
            shareButton.isHidden = true
        }
    }
}

class ToolbarTextField: AutocompleteTextField {


    dynamic var clearButtonTintColor: UIColor? {
        didSet {
            // only call if different
            // Clear previous tinted image that's cache and ask for a relayout
            tintedClearImage = nil
            setNeedsLayout()
        }
    }

    fileprivate var tintedClearImage: UIImage?


    // seperate out into an extension?
    override func layoutSubviews() {
        super.layoutSubviews()
        

        // Since we're unable to change the tint color of the clear image, we need to iterate through the
        // subviews, find the clear button, and tint it ourselves. Thanks to Mikael Hellman for the tip:
        // http://stackoverflow.com/questions/27944781/how-to-change-the-tint-color-of-the-clear-button-on-a-uitextfield
        for view in subviews as [UIView] {

            if let button = view as? UIButton {
                if let image = UIImage(named: "clear_textfield") {
                    if tintedClearImage == nil {
                        tintedClearImage = image
                    }

                    if button.imageView?.image != tintedClearImage {
                        button.setImage(tintedClearImage, for: UIControlState())
                        button.setImage(tintedClearImage, for: .highlighted)

                    }

                }
            }
        }
    }

    fileprivate func tintImage(_ image: UIImage, color: UIColor?) -> UIImage {
        guard let color = color else { return image }

        let size = image.size

        UIGraphicsBeginImageContextWithOptions(size, false, 2)
        let context = UIGraphicsGetCurrentContext()!
        image.draw(at: CGPoint.zero)

        context.setFillColor(color.cgColor)
        context.setBlendMode(CGBlendMode.overlay)
        context.setAlpha(1.0)

        let rect = CGRect(
            x: CGPoint.zero.x,
            y: CGPoint.zero.y,
            width: image.size.width,
            height: image.size.height)
        context.fill(rect)
        let tintedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return tintedImage
    }
}

