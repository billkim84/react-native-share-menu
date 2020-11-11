//
//  ShareMenuReactView.swift
//  RNShareMenu
//
//  Created by Gustavo Parreira on 28/07/2020.
//

import MobileCoreServices

@objc(ShareMenuReactView)
public class ShareMenuReactView: NSObject {
    static var viewDelegate: ReactShareViewDelegate?

    @objc
    static public func requiresMainQueueSetup() -> Bool {
        return false
    }

    public static func attachViewDelegate(_ delegate: ReactShareViewDelegate!) {
        guard (ShareMenuReactView.viewDelegate == nil) else { return }

        ShareMenuReactView.viewDelegate = delegate
    }

    public static func detachViewDelegate() {
        ShareMenuReactView.viewDelegate = nil
    }

    @objc(dismissExtension:)
    func dismissExtension(_ error: String?) {
        guard let extensionContext = ShareMenuReactView.viewDelegate?.loadExtensionContext() else {
            print("Error: \(NO_EXTENSION_CONTEXT_ERROR)")
            return
        }

        if error != nil {
            let exception = NSError(
                domain: Bundle.main.bundleIdentifier!,
                code: DISMISS_SHARE_EXTENSION_WITH_ERROR_CODE,
                userInfo: ["error": error!]
            )
            extensionContext.cancelRequest(withError: exception)
            return
        }

        extensionContext.completeRequest(returningItems: [], completionHandler: nil)
    }

    @objc
    func openApp() {
        guard let viewDelegate = ShareMenuReactView.viewDelegate else {
            print("Error: \(NO_DELEGATE_ERROR)")
            return
        }

        viewDelegate.openApp()
    }

    @objc(continueInApp:)
    func continueInApp(_ extraData: [String:Any]?) {
        guard let viewDelegate = ShareMenuReactView.viewDelegate else {
            print("Error: \(NO_DELEGATE_ERROR)")
            return
        }

        let extensionContext = viewDelegate.loadExtensionContext()

        guard let item = extensionContext.inputItems.first as? NSExtensionItem else {
            print("Error: \(COULD_NOT_FIND_ITEM_ERROR)")
            return
        }

        viewDelegate.continueInApp(with: item, and: extraData)
    }

    @objc(data:reject:)
    func data(_
            resolve: @escaping RCTPromiseResolveBlock,
            reject: @escaping RCTPromiseRejectBlock) {
        guard let extensionContext = ShareMenuReactView.viewDelegate?.loadExtensionContext() else {
            print("Error: \(NO_EXTENSION_CONTEXT_ERROR)")
            return
        }

        extractDataFromContext(context: extensionContext) { (data, mimeType, error) in
            guard (error == nil) else {
                reject("error", error?.description, nil)
                return
            }

            let s = MemoryLayout.size(ofValue: data);

            print("Data size s = \(s)")
            resolve([MIME_TYPE_KEY: mimeType, DATA_KEY: data])
        }
    }

    func extractDataFromContext(context: NSExtensionContext, withCallback callback: @escaping (String?, String?, NSException?) -> Void) {


        let item:NSExtensionItem! = context.inputItems.first as? NSExtensionItem
        let attachments:[AnyObject]! = item.attachments
        let myGroup = DispatchGroup()

        var urlProvider:NSItemProvider! = nil
//        var imageProvider:NSItemProvider! = nil
        var textProvider:NSItemProvider! = nil
        var dataProvider:NSItemProvider! = nil
        var imageProviders:[NSItemProvider] = []


        var allData: [String: Array<String>] = ["images": [], "urls": [], "text": [], "data": []]

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
                urlProvider = provider as? NSItemProvider

            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeText as String) {
                textProvider = provider as? NSItemProvider

            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeImage as String) {
                //imageProvider = provider as? NSItemProvider
                imageProviders.append(provider as! NSItemProvider)

            } else if provider.hasItemConformingToTypeIdentifier(kUTTypeData as String) {
                dataProvider = provider as? NSItemProvider

            }
        }

        if (urlProvider != nil) {
            myGroup.enter()
            urlProvider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) { (item, error) in
                let url: URL! = item as? URL

                allData["urls"]!.append(url.absoluteString)
                myGroup.leave()
            }
        }
        if (!imageProviders.isEmpty) {
            for imgProvier in imageProviders {
                myGroup.enter()
                imgProvier.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil) { (item, error) in
                    let url: URL! = item as? URL
                    let image: UIImage! = item as? UIImage

                    // item can be url or image data
                    if url != nil {
                        allData["images"]!.append(url.absoluteString)
                    }

                    // handle image data
                    if image != nil {

                        guard let groupFileManagerContainer = FileManager.default
                                .containerURL(forSecurityApplicationGroupIdentifier: "group.io.dulyapp.duly")
                        else {
                            return
                        }

                        // sotre file temporary
                        let fileName = UUID().uuidString
                        let filePath = groupFileManagerContainer
                          .appendingPathComponent("\(fileName).png")

                        if let data = image.pngData() {
                            try? data.write(to: filePath)
                        }

                        allData["images"]!.append(filePath.absoluteString)
                    }

                    myGroup.leave()
                }
            }


        }
        if (textProvider != nil) {
            myGroup.enter()
            textProvider.loadItem(forTypeIdentifier: kUTTypeText as String, options: nil) { (item, error) in
                let text:String! = item as? String

                allData["text"]!.append(text)
                myGroup.leave()
            }
        }
        if (dataProvider != nil) {
            myGroup.enter()
            dataProvider.loadItem(forTypeIdentifier: kUTTypeData as String, options: nil) { (item, error) in
                let url: URL! = item as? URL

                allData["data"]!.append(url.absoluteString)
                myGroup.leave()
            }
        }

        myGroup.notify(queue: .main) {
            print("Finished all requests.")

            if let theJSONData = try?  JSONSerialization.data(
              withJSONObject: allData,
              options: .prettyPrinted
              ),
              let theJSONText = String(data: theJSONData,
                                       encoding: String.Encoding.utf8) {
                  print("JSON string = \n\(theJSONText)")
                let s = MemoryLayout.size(ofValue: theJSONText);

                print("theJSONText size = \(s)")
                 callback(theJSONText, "text/plain", nil);
            }
        }
    }

    func moveFileToDisk(from srcUrl: URL, to destUrl: URL) -> Bool {
      do {
        if FileManager.default.fileExists(atPath: destUrl.path) {
          try FileManager.default.removeItem(at: destUrl)
        }
        try FileManager.default.copyItem(at: srcUrl, to: destUrl)
      } catch (let error) {
        print("Could not save file from \(srcUrl) to \(destUrl): \(error)")
        return false
      }

      return true
    }

    func extractMimeType(from url: URL) -> String {
      let fileExtension: CFString = url.pathExtension as CFString
      guard let extUTI = UTTypeCreatePreferredIdentifierForTag(
              kUTTagClassFilenameExtension,
              fileExtension,
              nil
      )?.takeUnretainedValue() else { return "" }

      guard let mimeUTI = UTTypeCopyPreferredTagWithClass(extUTI, kUTTagClassMIMEType)
      else { return "" }

      return mimeUTI.takeUnretainedValue() as String
    }
}
