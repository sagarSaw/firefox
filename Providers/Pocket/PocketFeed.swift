/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Alamofire
import Shared
import Deferred
import Storage

private let PocketEnvAPIKey = "PocketEnvironmentAPIKey"
private let PocketGlobalFeed = "https://getpocket.com/v3/firefox/global-recs"

/*

 The Pocket class is used to fetch stories from the Pocked API.
 Right now this only supports the global feed

 A sample feed item
 {
     "id":1615,
     "url":"https:\/\/pocket.co\/sMmr2K",
     "dedupe_url":"http:\/\/www.artofmanliness.com\/2017\/06\/28\/23-dangerous-things-let-kids\/",
     "title":"23 Dangerous Things You Should Let Your Kids Do",
     "excerpt":"Even though the modern world isn\u2019t any more dangerous than it was.",
     "domain":"artofmanliness.com",
     "image_src":"https:\/\/d33ypg4xwx0n86.cloudfront.net/blah.jpg",
     "published_timestamp":"1498626000",
     "sort_id":0
 }

 */

struct PocketStory {
    let url: URL
    let title: String
    let storyDescription: String
    let imageURL: URL
    let domain: String

    static func parseJSON(list: Array<[String: Any]>) -> [PocketStory] {
        return list.flatMap({ (storyDict) -> PocketStory? in
            guard let urlS = storyDict["url"] as? String, let domain = storyDict["domain"] as? String,
                let imageURLS = storyDict["image_src"] as? String,
                let title = storyDict["title"] as? String,
                let description = storyDict["storyDescription"] as? String else {
                    return nil
            }
            guard let url = URL(string: urlS), let imageURL = URL(string: imageURLS) else {
                return nil
            }
            var site = Site(url: urlS, title: title)
            site.f
            return PocketStory(url: url, title: title, storyDescription: description, imageURL: imageURL, domain: domain)
        })
    }
}

private class PocketError: MaybeErrorType {
    var description = "Failed to load from API"
}

class Pocket {

    // The request session. Cache policy needs to be configured correctly
    lazy fileprivate var alamofire: SessionManager = {
        let ua = UserAgent.defaultUserAgent()
        let configuration = URLSessionConfiguration.default
        return SessionManager.managerWithUserAgent(ua, configuration: configuration)
    }()

    // Fetch items from the global pocket feed
    func globalFeed(items: Int = 2) -> Deferred<Maybe<Array<PocketStory>>> {
        let deferred = Deferred<Maybe<Array<PocketStory>>>()

        guard let request = createGlobalFeedRequest(items: items) else {
            return deferMaybe(PocketError())
        }

        alamofire.request(request).validate(contentType: ["application/json"]).responseJSON { response in
            guard response.error == nil, let result = response.result.value as? [String: Any] else {
                return deferred.fill(Maybe(failure: PocketError()))
            }
            guard let items = result["list"] as? Array<[String: Any]> else {
                return deferred.fill(Maybe(failure: PocketError()))
            }
            return deferred.fill(Maybe(success: PocketStory.parseJSON(list: items)))
        }

        return deferred
    }

    // Create the URL request to query the Pocket API. The max items that the query can return is 20
    private func createGlobalFeedRequest(items: Int = 2) -> URLRequest? {
        guard items > 0 && items <= 20 else {
            return nil
        }

        let url = URL(string: PocketGlobalFeed)?.withQueryParam("count", value: "\(items)")
        guard let feedURL = url else {
            return nil
        }
        let apiURL = addAPIKey(url: feedURL)
        return URLRequest(url: apiURL, cachePolicy: URLRequest.CachePolicy.reloadIgnoringCacheData, timeoutInterval: 5)
    }

    private func addAPIKey(url: URL) -> URL {
        return url.withQueryParam("consumer_key", value: "")
    }

}






