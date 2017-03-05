import Foundation
#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
#else
    import Postbox
    import SwiftSignalKit
#endif

private func applyMediaResourceChanges(from: Media, to: Media, postbox: Postbox) {
    if let fromImage = from as? TelegramMediaImage, let toImage = to as? TelegramMediaImage {
        if let fromSmallestRepresentation = smallestImageRepresentation(fromImage.representations), let toSmallestRepresentation = smallestImageRepresentation(toImage.representations) {
            postbox.mediaBox.moveResourceData(from: fromSmallestRepresentation.resource.id, to: toSmallestRepresentation.resource.id)
        }
        if let fromLargestRepresentation = largestImageRepresentation(fromImage.representations), let toLargestRepresentation = largestImageRepresentation(toImage.representations) {
            postbox.mediaBox.moveResourceData(from: fromLargestRepresentation.resource.id, to: toLargestRepresentation.resource.id)
        }
    } else if let fromFile = from as? TelegramMediaFile, let toFile = to as? TelegramMediaFile {
        if let fromPreview = smallestImageRepresentation(fromFile.previewRepresentations), let toPreview = smallestImageRepresentation(toFile.previewRepresentations) {
            postbox.mediaBox.moveResourceData(from: fromPreview.resource.id, to: toPreview.resource.id)
        }
        postbox.mediaBox.moveResourceData(from: fromFile.resource.id, to: toFile.resource.id)
    }
}

func applyUpdateMessage(postbox: Postbox, stateManager: AccountStateManager, message: Message, result: Api.Updates) -> Signal<Void, NoError> {
    let messageId = result.rawMessageIds.first
    let apiMessage = result.messages.first
    
    return postbox.modify { modifier -> Void in
        var updatedTimestamp: Int32?
        if let apiMessage = apiMessage {
            switch apiMessage {
                case let .message(_, _, _, _, _, _, _, date, _, _, _, _, _, _):
                    updatedTimestamp = date
                case .messageEmpty:
                    break
                case let .messageService(_, _, _, _, _, date, _):
                    updatedTimestamp = date
            }
        } else {
            switch result {
                case let .updateShortSentMessage(_, _, _, _, date, _, _):
                    updatedTimestamp = date
                default:
                    break
            }
        }
        
        var sentStickers: [TelegramMediaFile] = []
        
        modifier.updateMessage(message.id, update: { currentMessage in
            let updatedId: MessageId
            if let messageId = messageId {
                updatedId = MessageId(peerId: currentMessage.id.peerId, namespace: Namespaces.Message.Cloud, id: messageId)
            } else {
                updatedId = currentMessage.id
            }
            
            let media: [Media]
            let attributes: [MessageAttribute]
            let text: String
            if let apiMessage = apiMessage, let updatedMessage = StoreMessage(apiMessage: apiMessage) {
                media = updatedMessage.media
                attributes = updatedMessage.attributes
                text = updatedMessage.text
            } else if case let .updateShortSentMessage(_, _, _, _, _, apiMedia, entities) = result {
                let (_, mediaValue) = textAndMediaFromApiMedia(apiMedia)
                if let mediaValue = mediaValue {
                    media = [mediaValue]
                } else {
                    media = []
                }
                
                var updatedAttributes: [MessageAttribute] = currentMessage.attributes
                if let entities = entities, !entities.isEmpty {
                    for i in 0 ..< updatedAttributes.count {
                        if updatedAttributes[i] is TextEntitiesMessageAttribute {
                            updatedAttributes.remove(at: i)
                            break
                        }
                    }
                    updatedAttributes.append(TextEntitiesMessageAttribute(entities: messageTextEntitiesFromApiEntities(entities)))
                }
                attributes = updatedAttributes
                text = currentMessage.text
            } else {
                media = currentMessage.media
                attributes = currentMessage.attributes
                text = currentMessage.text
            }
            
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date)
            }
            
            if let fromMedia = currentMessage.media.first, let toMedia = media.first {
                applyMediaResourceChanges(from: fromMedia, to: toMedia, postbox: postbox)
            }
            
            for media in media {
                if let file = media as? TelegramMediaFile, file.isSticker {
                    sentStickers.append(file)
                }
            }
            
            return StoreMessage(id: updatedId, globallyUniqueId: nil, timestamp: updatedTimestamp ?? currentMessage.timestamp, flags: [], tags: tagsForStoreMessage(media), forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: text, attributes: attributes, media: media)
        })
        if let updatedTimestamp = updatedTimestamp {
            modifier.offsetPendingMessagesTimestamps(lowerBound: message.id, timestamp: updatedTimestamp)
        }
        for file in sentStickers {
            modifier.addOrMoveToFirstPositionOrderedItemListItem(collectionId: Namespaces.OrderedItemList.CloudRecentStickers, item: OrderedItemListEntry(id: RecentMediaItemId(file.fileId).rawValue, contents: RecentMediaItem(file)), removeTailIfCountExceeds: 20)
        }
        stateManager.addUpdates(result)
    }
}