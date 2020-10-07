//
//  FireServer.swift
//  FireFuse
//
//  Created by Nicolas Degen on 25.08.20.
//  Copyright © 2020 Nicolas Degen. All rights reserved.
//

import FirebaseFirestore
import Fuse

func debugFatalError() {
  #if DEBUG
  fatalError()
  #endif
}

public class DataBindingHandler: BindingHandler {
  public func remove() {
    observerHandle?.remove()
  }
  
  var observerHandle: ListenerRegistration?
}

public class FireServer: FuseServer {

  var database: DocumentReference {
    #if DEBUG
    return Firestore.firestore().collection("devel").document("0.0.1")
    #else
    return Firestore.firestore().collection("releases").document("0.0.1")
    #endif
  }
  
  public func bind(toIds ids: [Id], dataOfType type: Fusable.Type, completion: @escaping ([Fusable]) -> ()) -> BindingHandler {
    if ids.isEmpty { return DataBindingHandler() }
    let handle = database.collection(type.typeId)
      .addSnapshotListener { (snapshot, error) in
        guard let querySnapshot = snapshot else { return }
        var newData = [Fusable]()
        for documentSnapshot in querySnapshot.documents {
          if let jsonData = documentSnapshot.jsonData() {
            do {
              let data = try type.decode(fromData: jsonData)
              newData.append(data)
            } catch {
              print(error.localizedDescription)
              jsonData.printUtf8()
              debugFatalError()
            }
          }
        }
        completion(newData)
      }
    let handler = DataBindingHandler()
    handler.observerHandle = handle
    return handler
  }
  

  
  public func bind(dataOfType type: Fusable.Type, matching constraints: [Constraint], completion: @escaping ([Fusable]) -> ()) -> BindingHandler {
    let handle = database.collection(type.typeId)
    var query: Query?
    
    for constraint in constraints {
      if let tmp = query {
        query = tmp.applyConstraint(constraint)
      } else {
        query = handle.applyConstraint(constraint)
      }
    }
    
    let callback: (QuerySnapshot?, Error?)->() = { (snapshot, error) in
      guard let querySnapshot = snapshot else { return }
      var newData = [Fusable]()
      for documentSnapshot in querySnapshot.documents {
        if let jsonData = documentSnapshot.jsonData() {
          do {
            let data = try type.decode(fromData: jsonData)
            newData.append(data)
          } catch {
            print(error.localizedDescription)
            jsonData.printUtf8()
            debugFatalError()
          }
        }
      }
      completion(newData)
    }
    
    let handler = DataBindingHandler()
    if let query = query {
      handler.observerHandle = query.addSnapshotListener(callback)
    } else {
      handler.observerHandle = handle.addSnapshotListener(callback)
    }
    return handler
  }
  
  public func bind(toId id: Id, ofDataType type: Fusable.Type, completion: @escaping (Fusable?) -> ()) -> BindingHandler {
    if id == "" { return DataBindingHandler() }
    let handle = database.collection(type.typeId).document(id).addSnapshotListener { (snapshot, error) in
      if let jsonData = snapshot?.jsonData() {
        if let data = try? type.decode(fromData: jsonData) {
          completion(data)
        } else {
          jsonData.printUtf8()
          debugFatalError()
        }
      }
    }
    let handler = DataBindingHandler()
    handler.observerHandle = handle
    return handler
  }
  
  public func get(id: Id, ofDataType type: Fusable.Type, completion: @escaping (Fusable?) -> ()) {
    if id == "" { completion(nil); return }
    database.collection(type.typeId).document(id).getDocument { (snapshot, error) in
      if let jsonData = snapshot?.jsonData() {
        if let storable = try? type.decode(fromData: jsonData) {
          completion(storable)
          return
        } else {
          debugFatalError()
        }
      }
      completion(nil)
    }
  }
  
  public func get(ids: [Id], ofDataType type: Fusable.Type, completion: @escaping ([Fusable]) -> ()) {
    var storables = [Fusable]()
    var number = ids.count
    
    if number == 0 {
      completion(storables)
    }
    
    for id in ids {
      if id == "" { continue }
      database.collection(type.typeId).document(id).getDocument { (snapshot, error) in
        number -= 1
        if let jsonData = snapshot?.jsonData() {
          if let storable = try? type.decode(fromData: jsonData) {
            storables.append(storable)
          } else {
            debugFatalError()
          }
        }
        if number == 0 {
          completion(storables)
        }
      }
    }
  }
  
  
  public func get(dataOfType type: Fusable.Type, matching constraints: [Constraint], completion: @escaping ([Fusable]) -> ()) {
    let callback: (QuerySnapshot?, Error?)->() = { (snapshot, error) in
      guard let query = snapshot else { return }
      var storables = [Fusable]()
      for jsonData in query.documents.compactMap({$0.jsonData()}) {
        if let storable = try? type.decode(fromData: jsonData) {
          storables.append(storable)
        } else {
          jsonData.printUtf8()
          debugFatalError()
        }
      }
      completion(storables)
    }
    
    let handle = database.collection(type.typeId)
    var query: Query?
    
    for constraint in constraints {
      if let tmp = query {
        query = tmp.applyConstraint(constraint)
      } else {
        query = handle.applyConstraint(constraint)
      }
    }
    if let query = query {
      query.getDocuments(completion: callback)
    } else {
      handle.getDocuments(completion: callback)
    }
  }
  
  public func set(_ storables: [Fusable], completion: SetterCompletion) {
    storables.forEach {
      database.collection(type(of: $0).typeId).document($0.id).setData($0)
    }
  }
  
  public func set(_ storable: Fusable, completion: SetterCompletion) {
    guard let dict = storable.parseDictionary() else { completion?(nil); return }
    database.collection(type(of: storable).typeId).document(storable.id).setData(dict) { error in
      completion?(error)
    }
  }
  
  func set(_ storable: Fusable) {
    database.collection(type(of: storable).typeId).document(storable.id).setData(storable)
  }
  
  public func delete(_ id: Id, forDataType type: Fusable.Type, completion: ((Error?) -> ())? = nil) {
    if id == "" { return }
    database.collection(type.typeId).document(id).delete { error in
      completion?(error)
    }
  }
  
  static var shared = FireServer()
  
  private init() {
    let settings = FirestoreSettings()
    settings.isPersistenceEnabled = true
    DefaultServerContainer.server = self
  }
}


public extension Data {
  func printUtf8() {
    print(String(data: self, encoding: .utf8) ?? "")
  }
}

extension DocumentSnapshot {
  func jsonData() -> Data? {
    if let data = self.data() as NSDictionary?  {
      return try? JSONSerialization.data(withJSONObject: data, options: [])
    }
    return nil
  }
}

extension CollectionReference {
  func applyConstraint(_ constraint: Constraint) -> Query? {
    switch constraint.relation {
    case .isEqual(let value):
      return self.whereField(constraint.field, isEqualTo: value)
    case .isContaining(let value):
      return self.whereField(constraint.field, arrayContains: value)
    case .isContainedIn(let values):
      return self.whereField(constraint.field, in: values)
    default:
      return nil
    }
  }
}

extension Query {
  func applyConstraint(_ constraint: Constraint) -> Query {
    switch constraint.relation {
    case .isEqual(let value):
      return self.whereField(constraint.field, isEqualTo: value)
    case .isContaining(let value):
      return self.whereField(constraint.field, arrayContains: value)
    case .isContainedIn(let values):
      return self.whereField(constraint.field, in: values)
    default:
      return self
    }
  }
}

extension DocumentReference {
  func setData(_ encodableDocument: Fusable) {
    guard let dict = encodableDocument.parseDictionary() else { return }
    self.setData(dict)
  }
}
