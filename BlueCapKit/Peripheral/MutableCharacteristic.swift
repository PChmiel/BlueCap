//
//  MutableCharacteristic.swift
//  BlueCap
//
//  Created by Troy Stribling on 8/9/14.
//  Copyright (c) 2014 Troy Stribling. The MIT License (MIT).
//

import Foundation
import CoreBluetooth

struct MutableCharacteristicIO {
    static let queue = Queue("us.gnos.mutable-characteristic")
}

public class MutableCharacteristic {

    private let profile  : CharacteristicProfile
    private var subscribers      = [NSUUID:CBCentralInjectable]()
    private var _isUpdating      = false

    internal var processWriteRequestPromise : StreamPromise<CBATTRequestInjectable>?
    internal weak var _service : MutableService?
    
    public let cbMutableChracteristic : CBMutableCharacteristic
    public var value : NSData?

    public var uuid : CBUUID {
        return self.profile.uuid
    }
    
    public var name : String {
        return self.profile.name
    }
    
    public var stringValues : [String] {
        return self.profile.stringValues
    }
    
    public var permissions : CBAttributePermissions {
        return self.cbMutableChracteristic.permissions
    }
    
    public var properties : CBCharacteristicProperties {
        return self.cbMutableChracteristic.properties
    }
    
    public var hasSubscriber : Bool {
        return self.subscribers.count > 0
    }
    
    public var isUpdating : Bool {
        return self._isUpdating
    }
    
    public var service : MutableService? {
        return self._service
    }

    public init(profile: CharacteristicProfile) {
        self.profile = profile
        self.value = profile.initialValue
        self.cbMutableChracteristic = CBMutableCharacteristic(type: profile.uuid, properties: profile.properties, value: nil, permissions: profile.permissions)
    }

    public init(uuid: String, properties: CBCharacteristicProperties, permissions: CBAttributePermissions, value: NSData?) {
        self.profile = CharacteristicProfile(uuid:uuid)
        self.value = value
        self.cbMutableChracteristic = CBMutableCharacteristic(type:self.profile.uuid, properties:properties, value:nil, permissions:permissions)
    }

    public convenience init(uuid:String, service: MutableService) {
        self.init(profile:CharacteristicProfile(uuid:uuid))
    }

    public func propertyEnabled(property:CBCharacteristicProperties) -> Bool {
        return (self.properties.rawValue & property.rawValue) > 0
    }
    
    public func permissionEnabled(permission:CBAttributePermissions) -> Bool {
        return (self.permissions.rawValue & permission.rawValue) > 0
    }

    public var stringValue : [String:String]? {
        if let value = self.value {
            return self.profile.stringValue(value)
        } else {
            return nil
        }
    }
    
    public func dataFromStringValue(stringValue: [String:String]) -> NSData? {
        return self.profile.dataFromStringValue(stringValue)
    }
    
    public func updateValueWithData(value: NSData) -> Bool  {
        return MutableCharacteristicIO.queue.sync {
            self.value = value
            if let peripheralManager = self.service?.peripheralManager where self._isUpdating &&
                    (self.propertyEnabled(.Notify)                    ||
                     self.propertyEnabled(.Indicate)                  ||
                     self.propertyEnabled(.NotifyEncryptionRequired)  ||
                     self.propertyEnabled(.IndicateEncryptionRequired)) {
                self._isUpdating = peripheralManager.updateValue(value, forCharacteristic:self)
            } else {
                self._isUpdating = false
            }
            return self._isUpdating
        }
    }
    
    public class func withProfiles(profiles: [CharacteristicProfile], service: MutableService) -> [MutableCharacteristic] {
        return profiles.map{MutableCharacteristic(profile: $0)}
    }
        
    public func startRespondingToWriteRequests(capacity: Int? = nil) -> FutureStream<CBATTRequestInjectable> {
        return MutableCharacteristicIO.queue.sync {
            self.processWriteRequestPromise = StreamPromise<CBATTRequestInjectable>(capacity:capacity)
            return self.processWriteRequestPromise!.future
        }
    }
    
    public func stopRespondingToWriteRequests() {
        MutableCharacteristicIO.queue.sync {
            self.processWriteRequestPromise = nil
        }
    }
    
    internal func didRespondToWriteRequest(request: CBATTRequestInjectable) -> Bool  {
        if let processWriteRequestPromise = self.processWriteRequestPromise {
            processWriteRequestPromise.success(request)
            return true
        } else {
            return false
        }
    }
    
    internal func didSubscribeToCharacteristic(central: CBCentralInjectable) {
        MutableCharacteristicIO.queue.sync {
            self.subscribers[central.identifier] = central
            self._isUpdating = true
        }
    }
    
    internal func didUnsubscribeFromCharacteristic(central: CBCentralInjectable) {
        MutableCharacteristicIO.queue.sync {
            self.subscribers.removeValueForKey(central.identifier)
            self._isUpdating = false
        }
    }

    public func peripheralManagerIsReadyToUpdateSubscribers() {
        MutableCharacteristicIO.queue.sync {
            if self.hasSubscriber {
                self._isUpdating = true
            }
        }
    }

    public func updateValueWithString(value: [String:String]) -> Bool {
        if let data = self.profile.dataFromStringValue(value) {
            return self.updateValueWithData(data)
        } else {
            return false
        }
    }
    
    public func respondToRequest(request: CBATTRequestInjectable, withResult result: CBATTError) {
        self.service?.peripheralManager?.respondToRequest(request, withResult:result)
    }
    
    public func updateValue<T:Deserializable>(value: T) -> Bool {
        return self.updateValueWithData(Serde.serialize(value))
    }

    public func updateValue<T:RawDeserializable>(value: T) -> Bool  {
        return self.updateValueWithData(Serde.serialize(value))
    }

    public func updateValue<T:RawArrayDeserializable>(value: T) -> Bool  {
        return self.updateValueWithData(Serde.serialize(value))
    }

    public func updateValue<T:RawPairDeserializable>(value: T) -> Bool  {
        return self.updateValueWithData(Serde.serialize(value))
    }

    public func updateValue<T:RawArrayPairDeserializable>(value: T) -> Bool  {
        return self.updateValueWithData(Serde.serialize(value))
    }

}