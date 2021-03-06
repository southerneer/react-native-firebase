#import "RNFirebaseFirestoreCollectionReference.h"

@implementation RNFirebaseFirestoreCollectionReference

#if __has_include(<FirebaseFirestore/FirebaseFirestore.h>)

static NSMutableDictionary *_listeners;

- (id)initWithPathAndModifiers:(RCTEventEmitter *) emitter
                           app:(NSString *) app
                          path:(NSString *) path
                       filters:(NSArray *) filters
                        orders:(NSArray *) orders
                       options:(NSDictionary *) options {
    self = [super init];
    if (self) {
        _emitter = emitter;
        _app = app;
        _path = path;
        _filters = filters;
        _orders = orders;
        _options = options;
        _query = [self buildQuery];
    }
    // Initialise the static listeners object if required
    if (!_listeners) {
        _listeners = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)get:(RCTPromiseResolveBlock) resolve
   rejecter:(RCTPromiseRejectBlock) reject {
    [_query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            [RNFirebaseFirestore promiseRejectException:reject error:error];
        } else {
            NSDictionary *data = [RNFirebaseFirestoreCollectionReference snapshotToDictionary:snapshot];
            resolve(data);
        }
    }];
}

+ (void)offSnapshot:(NSString *) listenerId {
    id<FIRListenerRegistration> listener = _listeners[listenerId];
    if (listener) {
        [_listeners removeObjectForKey:listenerId];
        [listener remove];
    }
}

- (void)onSnapshot:(NSString *) listenerId {
    if (_listeners[listenerId] == nil) {
        id listenerBlock = ^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (error) {
                id<FIRListenerRegistration> listener = _listeners[listenerId];
                if (listener) {
                    [_listeners removeObjectForKey:listenerId];
                    [listener remove];
                }
                [self handleQuerySnapshotError:listenerId error:error];
            } else {
                [self handleQuerySnapshotEvent:listenerId querySnapshot:snapshot];
            }
        };
        id<FIRListenerRegistration> listener = [_query addSnapshotListener:listenerBlock];
        _listeners[listenerId] = listener;
    }
}

- (FIRQuery *)buildQuery {
    FIRQuery *query = (FIRQuery*)[[RNFirebaseFirestore getFirestoreForApp:_app] collectionWithPath:_path];
    query = [self applyFilters:query];
    query = [self applyOrders:query];
    query = [self applyOptions:query];

    return query;
}

- (FIRQuery *)applyFilters:(FIRQuery *) query {
    for (NSDictionary *filter in _filters) {
        NSString *fieldPath = filter[@"fieldPath"];
        NSString *operator = filter[@"operator"];
        // TODO: Validate this works
        id value = filter[@"value"];

        if ([operator isEqualToString:@"EQUAL"]) {
            query = [query queryWhereField:fieldPath isEqualTo:value];
        } else if ([operator isEqualToString:@"GREATER_THAN"]) {
            query = [query queryWhereField:fieldPath isGreaterThan:value];
        } else if ([operator isEqualToString:@"GREATER_THAN_OR_EQUAL"]) {
            query = [query queryWhereField:fieldPath isGreaterThanOrEqualTo:value];
        } else if ([operator isEqualToString:@"LESS_THAN"]) {
            query = [query queryWhereField:fieldPath isLessThan:value];
        } else if ([operator isEqualToString:@"LESS_THAN_OR_EQUAL"]) {
            query = [query queryWhereField:fieldPath isLessThanOrEqualTo:value];
        }
    }
    return query;
}

- (FIRQuery *)applyOrders:(FIRQuery *) query {
    for (NSDictionary *order in _orders) {
        NSString *direction = order[@"direction"];
        NSString *fieldPath = order[@"fieldPath"];

        query = [query queryOrderedByField:fieldPath descending:([direction isEqualToString:@"DESCENDING"])];
    }
    return query;
}

- (FIRQuery *)applyOptions:(FIRQuery *) query {
    if (_options[@"endAt"]) {
        query = [query queryEndingAtValues:_options[@"endAt"]];
    }
    if (_options[@"endBefore"]) {
        query = [query queryEndingBeforeValues:_options[@"endBefore"]];
    }
    if (_options[@"offset"]) {
        // iOS doesn't support offset
    }
    if (_options[@"selectFields"]) {
        // iOS doesn't support selectFields
    }
    if (_options[@"startAfter"]) {
        query = [query queryStartingAfterValues:_options[@"startAfter"]];
    }
    if (_options[@"startAt"]) {
        query = [query queryStartingAtValues:_options[@"startAt"]];
    }
    return query;
}

- (void)handleQuerySnapshotError:(NSString *)listenerId
                           error:(NSError *)error {
    NSMutableDictionary *event = [[NSMutableDictionary alloc] init];
    [event setValue:_app forKey:@"appName"];
    [event setValue:_path forKey:@"path"];
    [event setValue:listenerId forKey:@"listenerId"];
    [event setValue:[RNFirebaseFirestore getJSError:error] forKey:@"error"];

    [_emitter sendEventWithName:FIRESTORE_COLLECTION_SYNC_EVENT body:event];
}

- (void)handleQuerySnapshotEvent:(NSString *)listenerId
                   querySnapshot:(FIRQuerySnapshot *)querySnapshot {
    NSMutableDictionary *event = [[NSMutableDictionary alloc] init];
    [event setValue:_app forKey:@"appName"];
    [event setValue:_path forKey:@"path"];
    [event setValue:listenerId forKey:@"listenerId"];
    [event setValue:[RNFirebaseFirestoreCollectionReference snapshotToDictionary:querySnapshot] forKey:@"querySnapshot"];

    [_emitter sendEventWithName:FIRESTORE_COLLECTION_SYNC_EVENT body:event];
}

+ (NSDictionary *)snapshotToDictionary:(FIRQuerySnapshot *)querySnapshot {
    NSMutableDictionary *snapshot = [[NSMutableDictionary alloc] init];
    [snapshot setValue:[self documentChangesToArray:querySnapshot.documentChanges] forKey:@"changes"];
    [snapshot setValue:[self documentSnapshotsToArray:querySnapshot.documents] forKey:@"documents"];

    return snapshot;
}

+ (NSArray *)documentChangesToArray:(NSArray<FIRDocumentChange *> *) documentChanges {
    NSMutableArray *changes = [[NSMutableArray alloc] init];
    for (FIRDocumentChange *change in documentChanges) {
        [changes addObject:[self documentChangeToDictionary:change]];
    }

    return changes;
}

+ (NSDictionary *)documentChangeToDictionary:(FIRDocumentChange *)documentChange {
    NSMutableDictionary *change = [[NSMutableDictionary alloc] init];
    [change setValue:[RNFirebaseFirestoreDocumentReference snapshotToDictionary:documentChange.document] forKey:@"document"];
    [change setValue:@(documentChange.newIndex) forKey:@"newIndex"];
    [change setValue:@(documentChange.oldIndex) forKey:@"oldIndex"];

    if (documentChange.type == FIRDocumentChangeTypeAdded) {
        [change setValue:@"added" forKey:@"type"];
    } else if (documentChange.type == FIRDocumentChangeTypeRemoved) {
        [change setValue:@"removed" forKey:@"type"];
    } else if (documentChange.type == FIRDocumentChangeTypeModified) {
        [change setValue:@"modified" forKey:@"type"];
    }

    return change;
}

+ (NSArray *)documentSnapshotsToArray:(NSArray<FIRDocumentSnapshot *> *) documentSnapshots {
    NSMutableArray *snapshots = [[NSMutableArray alloc] init];
    for (FIRDocumentSnapshot *snapshot in documentSnapshots) {
        [snapshots addObject:[RNFirebaseFirestoreDocumentReference snapshotToDictionary:snapshot]];
    }

    return snapshots;
}

#endif

@end
