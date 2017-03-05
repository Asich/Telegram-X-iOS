import Foundation
#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
#else
    import Postbox
    import SwiftSignalKit
#endif

public func removePeerChat(postbox: Postbox, peerId: PeerId) -> Signal<Void, NoError> {
    return postbox.modify { modifier -> Void in
        if peerId.namespace == Namespaces.Peer.SecretChat {
            if let state = modifier.getPeerChatState(peerId) as? SecretChatState {
                let updatedState = addSecretChatOutgoingOperation(modifier: modifier, peerId: peerId, operation: SecretChatOutgoingOperationContents.terminate, state: state).withUpdatedEmbeddedState(.terminated)
                if updatedState != state {
                    modifier.setPeerChatState(peerId, state: updatedState)
                    if let peer = modifier.getPeer(peerId) as? TelegramSecretChat {
                        updatePeers(modifier: modifier, peers: [peer.withUpdatedEmbeddedState(updatedState.embeddedState.peerState)], update: { _, updated in
                            return updated
                        })
                    }
                }
            }
            modifier.clearHistory(peerId)
            modifier.updatePeerChatListInclusion(peerId, inclusion: .never)
        } else {
            cloudChatAddRemoveChatOperation(modifier: modifier, peerId: peerId)
            if peerId.namespace == Namespaces.Peer.CloudUser  {
                modifier.updatePeerChatListInclusion(peerId, inclusion: .ifHasMessages)
                modifier.clearHistory(peerId)
            } else if peerId.namespace == Namespaces.Peer.CloudGroup {
                modifier.updatePeerChatListInclusion(peerId, inclusion: .never)
                modifier.clearHistory(peerId)
            } else {
                modifier.updatePeerChatListInclusion(peerId, inclusion: .never)
            }
        }
    }
}