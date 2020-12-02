import FirebaseFirestore
import Fuse
import FuseMock

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
  var database: DocumentReference
  
  public static var mock = MockServer()

  public init(path: String, host: String? = nil, sslEnabled: Bool = true, persistence: Bool = true) {
    
    let firestore = Firestore.firestore()
    let settings = firestore.settings
    
    if let host = host {
      settings.host = host
    }
    settings.isSSLEnabled = sslEnabled
    
    settings.isPersistenceEnabled = persistence
    firestore.settings = settings
    self.database = firestore.document(path)
  }
  
  public func bind(dataOfType type: Fusable.Type, matching constraints: [Constraint], completion: @escaping ([Fusable]) -> ()) -> BindingHandler {
    let handle = database.collection(type.typeId)
    var query: Query?
    
    if constraints.isEmpty {
      return DataBindingHandler()
    }
    
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
          jsonData.printUtf8()
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
            jsonData.printUtf8()
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
    if constraints.isEmpty {
      return
    }
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
  
  public func update(_ storable: Fusable, completion: FuseCompletion) {
    guard let dict = storable.parseDictionary() else { completion?(nil); return }
    database.collection(type(of: storable).typeId).document(storable.id).updateData(dict) { error in
      completion?(error)
    }
  }
  
  // Currently only supports tld fields
  public func update(_ storable: Fusable, on fields: [String], completion: FuseCompletion) {
    guard let dict = storable.parseDictionary() else { completion?(nil); return }
    let filtered = dict.filter { fields.contains($0.key) }
    database.collection(type(of: storable).typeId).document(storable.id).updateData(filtered) { error in
      completion?(error)
    }
  }
  
  public func update(_ storables: [Fusable], completion: FuseCompletion) {
    storables.forEach { update($0, completion: completion) }
  }
  
  public func set(_ storables: [Fusable], merge: Bool, completion: FuseCompletion) {
    storables.forEach {
      set($0, merge: merge, completion: completion)
    }
  }
  
  public func set(_ storable: Fusable, merge: Bool, completion: FuseCompletion) {
    guard let dict = storable.parseDictionary() else { completion?(nil); return }
    database.collection(type(of: storable).typeId).document(storable.id).setData(dict, merge: merge) { error in
      completion?(error)
    }
  }
  
  
  public func set(_ storable: Fusable) {
    database.collection(type(of: storable).typeId).document(storable.id).setData(storable)
  }
  
  public func delete(_ id: Id, forDataType type: Fusable.Type, completion: ((Error?) -> ())? = nil) {
    if id == "" { return }
    database.collection(type.typeId).document(id).delete { error in
      completion?(error)
    }
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
      return self.whereField(constraint.field, in: Array(values.prefix(10)))
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
