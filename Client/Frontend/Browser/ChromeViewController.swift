//
//  ChromeViewController.swift
//  Client
//
//  Created by Farhan Patel on 6/2/17.
//  Copyright © 2017 Mozilla. All rights reserved.
//

/*
 The goal of the ChromeViewController is to slim down BVC. Its more of a viewController in name. It'll take a URLBarView, Tabmanager and BVC as inputs 
 and handle communication between them.
 
 a lot of the communication between urlbarview->BVC is just the BVC passing events to the tabmanager. Lets just create a seperate class for it instead. 
 Later we can add the bottom bar and simplify BVC further. Once we finish that we are left with a BVC that repersents only the webview frame!
 
 ChromeVC will act as the delegate of the URLBarView instead of BVC

 */

import Foundation
import XCGLogger
import Shared
import Storage
import Telemetry
import WebKit

private let log = Logger.browserLogger

protocol ChromeDelegate: class {
    func showHomePanels(_ show: Bool) //bad name
    func tabTrayButtonPressed()
    func readerModeActive(_ active: Bool)
    func presentModalViewController(_ modalVC: UIViewController)

    // Too Lazy to change for now
    func urlBar(_ urlBar: URLBarView, didEnterText text: String)
    func urlBarDidPressScrollToTop(_ urlBar: URLBarView)
    func tabToolbarDidPressMenu(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidPressShare(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidPressHomePage(_ tabToolbar: TabToolbarProtocol, button: UIButton)
}

class ChromeViewController: URLBarDelegate, TabToolbarDelegate {
    let tabManager: TabManager
    let urlBar: URLBarView
    let profile: Profile
    weak var delegate: ChromeDelegate?

    // location label actions
    fileprivate var pasteGoAction: AccessibleAction!
    fileprivate var pasteAction: AccessibleAction!
    fileprivate var copyAddressAction: AccessibleAction!

    init(tabManager: TabManager, urlBar: URLBarView, profile: Profile, delegate: ChromeDelegate) {
        self.tabManager = tabManager
        self.urlBar = urlBar
        self.profile = profile
        self.delegate = delegate

        // UIAccessibilityCustomAction subclass holding an AccessibleAction instance does not work, thus unable to generate AccessibleActions and UIAccessibilityCustomActions "on-demand" and need to make them "persistent" e.g. by being stored in BVC
        pasteGoAction = AccessibleAction(name: NSLocalizedString("Paste & Go", comment: "Paste the URL into the location bar and visit"), handler: { () -> Bool in
            if let pasteboardContents = UIPasteboard.general.string {
                self.urlBar(self.urlBar, didSubmitText: pasteboardContents)
                return true
            }
            return false
        })
        pasteAction = AccessibleAction(name: NSLocalizedString("Paste", comment: "Paste the URL into the location bar"), handler: { () -> Bool in
            if let pasteboardContents = UIPasteboard.general.string {
                // Enter overlay mode and fire the text entered callback to make the search controller appear.
                self.urlBar.enterOverlayMode(pasteboardContents, pasted: true)
                self.urlBar(self.urlBar, didEnterText: pasteboardContents)
                return true
            }
            return false
        })
        copyAddressAction = AccessibleAction(name: NSLocalizedString("Copy Address", comment: "Copy the URL from the location bar"), handler: { () -> Bool in
            if let url = self.urlBar.currentURL {
                UIPasteboard.general.url = url as URL
            }
            return true
        })

    }

    // needs passthrough
    func urlBarDidPressTabs(_ urlBar: URLBarView) {
        delegate?.tabTrayButtonPressed()
    }

    func urlBarDidPressReaderMode(_ urlBar: URLBarView) {
        if let tab = tabManager.selectedTab {
            if let readerMode = tab.getHelper(name: "ReaderMode") as? ReaderMode {
                switch readerMode.state {
                case .available:
                    print("call")
                    delegate?.readerModeActive(true)
                case .active:
                    print("call")
                   delegate?.readerModeActive(false)
                case .unavailable:
                    break
                }
            }
        }
    }

    // Looks good
    func urlBarDidLongPressReaderMode(_ urlBar: URLBarView) -> Bool {
        guard let tab = tabManager.selectedTab,
            let url = tab.url?.displayURL,
            let result = profile.readingList?.createRecordWithURL(url.absoluteString, title: tab.title ?? "", addedBy: UIDevice.current.name)
            else {
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NSLocalizedString("Could not add page to Reading list", comment: "Accessibility message e.g. spoken by VoiceOver after adding current webpage to the Reading List failed."))
                return false
        }

        switch result {
        case .success:
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NSLocalizedString("Added page to Reading List", comment: "Accessibility message e.g. spoken by VoiceOver after the current page gets added to the Reading List using the Reader View button, e.g. by long-pressing it or by its accessibility custom action."))
        // TODO: https://bugzilla.mozilla.org/show_bug.cgi?id=1158503 provide some form of 'this has been added' visual feedback?
        case .failure(let error):
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NSLocalizedString("Could not add page to Reading List. Maybe it's already there?", comment: "Accessibility message e.g. spoken by VoiceOver after the user wanted to add current page to the Reading List and this was not done, likely because it already was in the Reading List, but perhaps also because of real failures."))
            log.error("readingList.createRecordWithURL(url: \"\(url.absoluteString)\", ...) failed with error: \(error)")
        }
        return true
    }

    // Looks good
    func locationActionsForURLBar(_ urlBar: URLBarView) -> [AccessibleAction] {
        if UIPasteboard.general.string != nil {
            return [pasteGoAction, pasteAction, copyAddressAction]
        } else {
            return [copyAddressAction]
        }
    }

    // Looks good
    func urlBarDisplayTextForURL(_ url: URL?) -> String? {
        // use the initial value for the URL so we can do proper pattern matching with search URLs
        var searchURL = self.tabManager.selectedTab?.currentInitialURL
        if searchURL?.isErrorPageURL ?? true {
            searchURL = url
        }
        return profile.searchEngines.queryForSearchURL(searchURL as URL?) ?? url?.absoluteString
    }

    //Pass the popover back to the BVC
    func urlBarDidLongPressLocation(_ urlBar: URLBarView) {
        let longPressAlertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        for action in locationActionsForURLBar(urlBar) {
            longPressAlertController.addAction(action.alertAction(style: .default))
        }

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: "Label for Cancel button"), style: .cancel, handler: { (alert: UIAlertAction) -> Void in
        })
        longPressAlertController.addAction(cancelAction)

        if let popoverPresentationController = longPressAlertController.popoverPresentationController {
            popoverPresentationController.sourceView = urlBar
            popoverPresentationController.sourceRect = urlBar.frame
            popoverPresentationController.permittedArrowDirections = .any
      //      popoverPresentationController.delegate = self
        }

        if longPressAlertController.popoverPresentationController != nil {
       //     displayedPopoverController = longPressAlertController
        //    updateDisplayedPopoverProperties = setupPopover
        }
        delegate?.presentModalViewController(longPressAlertController)
       // self.present(longPressAlertController, animated: true, completion: nil)
    }

    //needs passthrough
    func urlBarDidPressScrollToTop(_ urlBar: URLBarView) {
        delegate?.urlBarDidPressScrollToTop(urlBar)
    }

    //Looks good
    func urlBarLocationAccessibilityActions(_ urlBar: URLBarView) -> [UIAccessibilityCustomAction]? {
        return locationActionsForURLBar(urlBar).map { $0.accessibilityCustomAction }
    }

    // Move search controller into here?
    // Pass through for now
    func urlBar(_ urlBar: URLBarView, didEnterText text: String) {
        delegate?.urlBar(urlBar, didEnterText: text)
    }
    // Looks good
    func urlBar(_ urlBar: URLBarView, didSubmitText text: String) {
        if let fixupURL = URIFixup.getURL(text) {
            // The user entered a URL, so use it.
            finishEditingAndSubmit(fixupURL, visitType: VisitType.typed)
            return
        }

        // We couldn't build a URL, so check for a matching search keyword.
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        guard let possibleKeywordQuerySeparatorSpace = trimmedText.characters.index(of: " ") else {
            submitSearchText(text)
            return
        }

        let possibleKeyword = trimmedText.substring(to: possibleKeywordQuerySeparatorSpace)
        let possibleQuery = trimmedText.substring(from: trimmedText.index(after: possibleKeywordQuerySeparatorSpace))

        profile.bookmarks.getURLForKeywordSearch(possibleKeyword).uponQueue(.main) { result in
            if var urlString = result.successValue,
                let escapedQuery = possibleQuery.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed),
                let range = urlString.range(of: "%s") {
                urlString.replaceSubrange(range, with: escapedQuery)

                if let url = URL(string: urlString) {
                    self.finishEditingAndSubmit(url, visitType: VisitType.typed)
                    return
                }
            }

            self.submitSearchText(text)
        }
    }
    // Looks good
    fileprivate func submitSearchText(_ text: String) {
        let engine = profile.searchEngines.defaultEngine

        if let searchURL = engine.searchURLForQuery(text) {
            // We couldn't find a matching search keyword, so do a search query.
            Telemetry.recordEvent(SearchTelemetry.makeEvent(engine, source: .URLBar))
            finishEditingAndSubmit(searchURL, visitType: VisitType.typed)
        } else {
            // We still don't have a valid URL, so something is broken. Give up.
            log.error("Error handling URL entry: \"\(text)\".")
            assertionFailure("Couldn't generate search URL: \(text)")
        }
    }

    // Looks good. But pass this through?
    fileprivate func resetSpoofedUserAgentIfRequired(_ webView: WKWebView, newURL: URL) {
        // Reset the UA when a different domain is being loaded
        if webView.url?.host != newURL.host {
            webView.customUserAgent = nil
        }
    }

    //TODO: not record event
    fileprivate func finishEditingAndSubmit(_ url: URL, visitType: VisitType) {
        urlBar.currentURL = url
        urlBar.leaveOverlayMode()

        guard let tab = tabManager.selectedTab else {
            return
        }

        if let webView = tab.webView {
            resetSpoofedUserAgentIfRequired(webView, newURL: url)
        }

        if let nav = tab.loadRequest(PrivilegedRequest(url: url) as URLRequest) {
           // self.recordNavigationInTab(tab, navigation: nav, visitType: visitType)
        }
    }
    // show homePanel delegate?
    func urlBarDidEnterOverlayMode(_ urlBar: URLBarView) {
        delegate?.showHomePanels(true)
    }

    //show homePanel delegate
    func urlBarDidLeaveOverlayMode(_ urlBar: URLBarView) {
        delegate?.showHomePanels(false)
    }

    // Looks good
    func tabToolbarDidPressBack(_ tabToolbar: TabToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.goBack()
    }

    //Pass through?
    func tabToolbarDidLongPressBack(_ tabToolbar: TabToolbarProtocol, button: UIButton) {
        showBackForwardList()
    }

    //Pass through. coallace into one
    func tabToolbarDidLongPressForward(_ tabToolbar: TabToolbarProtocol, button: UIButton) {
        showBackForwardList()
    }

    // Looks good
    func tabToolbarDidPressReload(_ tabToolbar: TabToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.reload()
    }

    // Looks good
    func tabToolbarDidPressStop(_ tabToolbar: TabToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.stop()
    }

    // Looks good
    func tabToolbarDidPressForward(_ tabToolbar: TabToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.goForward()
    }

    //pass the controler to BVC
    func tabToolbarDidLongPressReload(_ tabToolbar: TabToolbarProtocol, button: UIButton) {

        guard let tab = tabManager.selectedTab, tab.webView?.url != nil && (tab.getHelper(name: ReaderMode.name()) as? ReaderMode)?.state != .active else {
            return
        }

        let toggleActionTitle: String
        if tab.desktopSite {
            toggleActionTitle = NSLocalizedString("Request Mobile Site", comment: "Action Sheet Button for Requesting the Mobile Site")
        } else {
            toggleActionTitle = NSLocalizedString("Request Desktop Site", comment: "Action Sheet Button for Requesting the Desktop Site")
        }

        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.addAction(UIAlertAction(title: toggleActionTitle, style: .default, handler: { _ in tab.toggleDesktopSite() }))
        controller.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment:"Label for Cancel button"), style: .cancel, handler: nil))
     //   controller.popoverPresentationController?.sourceView = toolbar ?? urlBar
        controller.popoverPresentationController?.sourceRect = button.frame
     //   present(controller, animated: true, completion: nil)
        delegate?.presentModalViewController(controller)
    }


    func tabToolbarDidPressMenu(_ tabToolbar: TabToolbarProtocol, button: UIButton) {
        delegate?.tabToolbarDidPressMenu(tabToolbar, button: button)
    }

    fileprivate func setNoImageMode(_ enabled: Bool) {
        self.profile.prefs.setBool(enabled, forKey: PrefsKeys.KeyNoImageModeStatus)
        for tab in self.tabManager.tabs {
            tab.setNoImageMode(enabled, force: true)
        }
        self.tabManager.selectedTab?.reload()
    }

    func toggleBookmarkForTabState(_ tabState: TabState) {
        if tabState.isBookmarked {
            self.removeBookmark(tabState)
        } else {
            self.addBookmark(tabState)
        }
    }

    func addBookmark(_ tabState: TabState) {
        guard let url = tabState.url else { return }
        let absoluteString = url.absoluteString
        let shareItem = ShareItem(url: absoluteString, title: tabState.title, favicon: tabState.favicon)
        _ = profile.bookmarks.shareItem(shareItem)
        var userData = [QuickActions.TabURLKey: shareItem.url]
        if let title = shareItem.title {
            userData[QuickActions.TabTitleKey] = title
        }
        // Too long
        QuickActions.sharedInstance.addDynamicApplicationShortcutItemOfType(.openLastBookmark,
                                                                            withUserData: userData,
                                                                            toApplication: UIApplication.shared)
        if let tab = tabManager.getTabForURL(url) {
            tab.isBookmarked = true
        }
    }

    fileprivate func removeBookmark(_ tabState: TabState) {
        guard let url = tabState.url else { return }
        let absoluteString = url.absoluteString
        profile.bookmarks.modelFactory >>== {
            $0.removeByURL(absoluteString).uponQueue(.main) { res in
                if res.isSuccess, let tab = self.tabManager.getTabForURL(url) {
                    tab.isBookmarked = false
                }
            }
        }
    }

    func tabToolbarDidPressBookmark(_ tabToolbar: TabToolbarProtocol, button: UIButton) {
        guard let tab = tabManager.selectedTab,
            let _ = tab.url?.displayURL?.absoluteString else {
                log.error("Bookmark error: No tab is selected, or no URL in tab.")
                return
        }

        toggleBookmarkForTabState(tab.tabState)
    }

    // Nothing here?
    func tabToolbarDidLongPressBookmark(_ tabToolbar: TabToolbarProtocol, button: UIButton) {

    }

    //pass through
    func tabToolbarDidPressShare(_ tabToolbar: TabToolbarProtocol, button: UIButton) {
        delegate?.tabToolbarDidPressShare(tabToolbar, button: button)
    }

    // Pass through
    func tabToolbarDidPressHomePage(_ tabToolbar: TabToolbarProtocol, button: UIButton) {
        delegate?.tabToolbarDidPressHomePage(tabToolbar, button: button)
    }

    // show be in BVC
    func showBackForwardList() {
        if let backForwardList = tabManager.selectedTab?.webView?.backForwardList {
            let backForwardViewController = BackForwardListViewController(profile: profile, backForwardList: backForwardList, isPrivate: tabManager.selectedTab?.isPrivate ?? false)
            backForwardViewController.tabManager = tabManager
          //  backForwardViewController.bvc = self
            backForwardViewController.modalPresentationStyle = UIModalPresentationStyle.overCurrentContext
            backForwardViewController.backForwardTransitionDelegate = BackForwardListAnimator()
            delegate?.presentModalViewController(backForwardViewController)
        }
    }



}
