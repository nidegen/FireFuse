import FirebaseFirestore
import FirebaseFirestoreSwift
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

  public init(path: String = "", host: String? = nil, sslEnabled: Bool = true, persistence: Bool = true) {
    
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
  
  public func bind(dataType type: Fusable.Type, matching constraints: [Constraint], completion: @escaping GetArrayCompletion) -> BindingHandler {
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
      if let error = error {
        completion(.failure(error))
      }
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
      completion(.success(newData))
    }
    
    let handler = DataBindingHandler()
    if let query = query {
      handler.observerHandle = query.addSnapshotListener(callback)
    } else {
      handler.observerHandle = handle.addSnapshotListener(callback)
    }
    return handler
  }
  
  public func bind(toId id: Id, ofDataType type: Fusable.Type, completion: @escaping GetValueCompletion) -> BindingHandler {
    if id == "" { return DataBindingHandler() }
    let handle = database.collection(type.typeId).document(id).addSnapshotListener { (snapshot, error) in
      if let error = error {
        completion(.failure(error))
      } else if let jsonData = snapshot?.jsonData() {
        if let data = try? type.decode(fromData: jsonData) {
          completion(.success(data))
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
  
  public func get(id: Id, ofDataType type: Fusable.Type, source: DataSource, completion: @escaping GetValueCompletion) {
    if id == "" { completion(.success(nil)); return }
    database.collection(type.typeId).document(id)
      .getDocument(source: source.firebaseSource) { (snapshot, error) in
      if let jsonData = snapshot?.jsonData() {
        if let storable = try? type.decode(fromData: jsonData) {
          completion(.success(storable))
          return
        } else {
          jsonData.printUtf8()
          debugFatalError()
        }
      } else if let error = error {
        completion(.failure(error))
      }
      completion(.success(nil))
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
      database.collection(type.typeId).document(id)
        .getDocument { (snapshot, error) in
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
  
  
  public func get(dataType type: Fusable.Type, matching constraints: [Constraint], source: DataSource, completion: @escaping GetArrayCompletion) {

    let callback: (QuerySnapshot?, Error?)->() = { (snapshot, error) in
      if let error = error {
        completion(.failure(error))
      }
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
      completion(.success(storables))
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
      query.getDocuments(source: source.firebaseSource, completion: callback)
    } else {
      handle.getDocuments(source: source.firebaseSource, completion: callback)
    }
  }
  
  public func update(_ storable: Fusable, completion: SetCompletion) {
    guard let dict = storable.dictionaryDroppingId else { completion?(nil); return }
    database.collection(type(of: storable).typeId).document(storable.id).updateData(dict) { error in
      completion?(error)
    }
  }
  
  // Currently only supports tld fields
  public func update(_ storable: Fusable, on fields: [String], completion: SetCompletion) {
    guard let dict = storable.dictionaryDroppingId else { completion?(nil); return }
    let filtered = dict.filter { fields.contains($0.key) }
    database.collection(type(of: storable).typeId).document(storable.id).updateData(filtered) { error in
      completion?(error)
    }
  }
  
  public func update(_ storables: [Fusable], completion: SetCompletion) {
    storables.forEach { update($0, completion: completion) }
  }
  
  public func increment<T:Fusable>(fusable: T, field: String, value: Int64) {
    database.collection(type(of: fusable).typeId).document(fusable.id).updateData([field: FieldValue.increment(value)])
  }
  
  public func set(_ storables: [Fusable], merge: Bool, completion: SetCompletion) {
    storables.forEach {
      set($0, merge: merge, completion: completion)
    }
  }
  
  public func set(_ storable: Fusable, merge: Bool, completion: SetCompletion) {
    guard let dict = storable.dictionaryDroppingId else { completion?(nil); return }
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
      data.setValue(self.documentID, forKey: "id")
      return try? JSONSerialization.data(withJSONObject: data, options: [])
    }
    return nil
  }
}

extension Constraint {
  var fieldPath: FieldPath {
    let pathComponents = field.split{$0 == "."}.map(String.init)
    return FieldPath(pathComponents)
  }
}

extension CollectionReference {
  func applyConstraint(_ constraint: Constraint) -> Query? {
    var field = constraint.fieldPath
    if constraint.field == "id" {
      field = FieldPath.documentID()
    }
    switch constraint.relation {
    case .isEqual(let value):
      return self.whereField(field, isEqualTo: value)
    case .isContaining(let value):
      return self.whereField(field, arrayContains: value)
    case .isContainedIn(let values):
      return self.whereField(field, in: Array(values.prefix(10)))
    case .ordered(ascending: let ascending):
      return self.order(by: field, descending: !ascending)
    default:
      return nil
    }
  }
}

extension Query {
  func applyConstraint(_ constraint: Constraint) -> Query {
    var field = constraint.fieldPath
    if constraint.field == "id" {
      field = FieldPath.documentID()
    }
    switch constraint.relation {
    case .isEqual(let value):
      return self.whereField(field, isEqualTo: value)
    case .isContaining(let value):
      return self.whereField(field, arrayContains: value)
    case .isContainedIn(let values):
      return self.whereField(field, in: values)
    case .ordered(ascending: let ascending):
      return self.order(by: field, descending: !ascending)
    default:
      return self
    }
  }
}

extension Fusable {
  #warning("Use extension provided by future Fuse release")
  var dictionaryDroppingId: [String: Any]? {
    var dict = self.parseDictionary()
    dict?["id"] = nil
    return dict
  }
}

extension DocumentReference {
  func setData(_ encodableDocument: Fusable) {
    guard let dict = encodableDocument.dictionaryDroppingId else { return }
    self.setData(dict)
  }
}

extension Fuse.DataSource {
  var firebaseSource: FirestoreSource {
    switch self {
    case .cacheOnly:
      return .cache
    case .serverOnly:
      return .server
    case .serverOrCache:
      return .default
    }
  }
}
