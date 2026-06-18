import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class DoctorPatientChatContext {
  final String doctorId;
  final String doctorName;
  final String patientId;
  final String patientName;

  const DoctorPatientChatContext({
    required this.doctorId,
    required this.doctorName,
    required this.patientId,
    required this.patientName,
  });
}

class DoctorPatientChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String messageType;
  final String text;
  final String imageUrl;
  final String imagePath;
  final String imageBucket;
  final String imageBase64;
  final String voicePath;
  final String voiceBucket;
  final int voiceDurationMs;
  final DateTime? sentAt;

  const DoctorPatientChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.messageType,
    required this.text,
    required this.imageUrl,
    required this.imagePath,
    required this.imageBucket,
    required this.imageBase64,
    required this.voicePath,
    required this.voiceBucket,
    required this.voiceDurationMs,
    required this.sentAt,
  });

  bool get isImage => messageType == 'image';
  bool get isVoice => messageType == 'voice';

  factory DoctorPatientChatMessage.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return DoctorPatientChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      senderRole: data['senderRole'] as String? ?? '',
      messageType: data['messageType'] as String? ?? 'text',
      text: data['text'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      imagePath: data['imagePath'] as String? ?? '',
      imageBucket: data['imageBucket'] as String? ?? '',
      imageBase64: data['imageBase64'] as String? ?? '',
      voicePath: data['voicePath'] as String? ?? '',
      voiceBucket: data['voiceBucket'] as String? ?? '',
      voiceDurationMs: data['voiceDurationMs'] as int? ?? 0,
      sentAt: _parseDateTime(data['sentAt']),
    );
  }
}

class DoctorPatientChatService {
  static const String _collection = 'doctor_patient_chats';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String chatIdFor({required String doctorId, required String patientId}) {
    return '${doctorId}_$patientId';
  }

  Stream<List<DoctorPatientChatMessage>> watchMessages({
    required String doctorId,
    required String patientId,
  }) {
    return _messagesRef(doctorId: doctorId, patientId: patientId)
        .orderBy('sentAt')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(DoctorPatientChatMessage.fromDoc)
            .toList(growable: false));
  }

  Future<DoctorPatientChatContext?> loadCurrentPatientChatContext() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final patientDoc =
        await _firestore.collection('patients').doc(user.uid).get();
    if (!patientDoc.exists) return null;

    final data = patientDoc.data() ?? <String, dynamic>{};
    final doctorId = data['assignedDoctorId'] as String? ?? '';
    if (doctorId.trim().isEmpty) return null;

    return DoctorPatientChatContext(
      doctorId: doctorId,
      doctorName: await _resolveUserName(userId: doctorId, isDoctor: true),
      patientId: user.uid,
      patientName: _extractName(data, 'Patient'),
    );
  }

  Future<void> sendTextMessage({
    required String doctorId,
    required String patientId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await _writeMessage(
      doctorId: doctorId,
      patientId: patientId,
      messageType: 'text',
      text: trimmed,
      imageUrl: '',
      imagePath: '',
      imageBucket: '',
      imageBase64: '',
      lastMessage: trimmed,
    );
  }

  Future<void> sendImageMessage({
    required String doctorId,
    required String patientId,
    required XFile imageFile,
  }) async {
    await _ensureAccess(doctorId: doctorId, patientId: patientId);

    final messageRef =
        _messagesRef(doctorId: doctorId, patientId: patientId).doc();
    final imageBytes = await imageFile.readAsBytes();
    final fileExt = _fileExtensionFromPath(imageFile.path);
    final imagePath =
        'doctor_patient_chats/$doctorId/$patientId/${messageRef.id}.$fileExt';

    final inlineBase64 = _compressAndEncodeInlineImage(imageBytes);

    String uploadedBucket = '';
    bool uploadedToStorage = false;

    try {
      uploadedBucket = await _uploadImageWithBucketFallback(
        imagePath: imagePath,
        imageBytes: imageBytes,
        localImagePath: imageFile.path,
        contentType: _contentTypeForExtension(fileExt),
      );
      uploadedToStorage = true;
    } on FirebaseException catch (e) {
      // Fallback to Firestore inline image if Storage bucket/rules are failing.
      debugPrint(
          '[DoctorPatientChatService] Storage upload failed [${e.code}], falling back to inline image.');
    }

    await _writeMessage(
      doctorId: doctorId,
      patientId: patientId,
      messageType: 'image',
      text: '',
      imageUrl: '',
      imagePath: uploadedToStorage ? imagePath : '',
      imageBucket: uploadedToStorage ? uploadedBucket : '',
      imageBase64: uploadedToStorage ? '' : inlineBase64,
      lastMessage: 'Image',
      messageId: messageRef.id,
    );
  }

  Future<void> sendVoiceMessage({
    required String doctorId,
    required String patientId,
    required String filePath,
    required int durationMs,
  }) async {
    await _ensureAccess(doctorId: doctorId, patientId: patientId);

    final messageRef =
        _messagesRef(doctorId: doctorId, patientId: patientId).doc();
    final voiceStoragePath =
        'doctor_patient_chats/$doctorId/$patientId/${messageRef.id}.m4a';

    String uploadedBucket = '';
    bool uploadedToStorage = false;
    String inlineBase64 = '';

    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      inlineBase64 = base64Encode(bytes); // Prepare fallback

      uploadedBucket = await _uploadImageWithBucketFallback(
        imagePath: voiceStoragePath,
        imageBytes: bytes,
        localImagePath: filePath,
        contentType: 'audio/m4a',
      );
      uploadedToStorage = true;
    } on FirebaseException catch (e) {
      debugPrint(
          '[DoctorPatientChatService] Voice upload failed [${e.code}], falling back to inline base64.');
    } catch (e) {
      debugPrint(
          '[DoctorPatientChatService] Voice upload error: $e, falling back to inline base64.');
    }

    await _writeMessage(
      doctorId: doctorId,
      patientId: patientId,
      messageType: 'voice',
      text: '',
      imageUrl: '',
      imagePath: '',
      imageBucket: '',
      imageBase64: uploadedToStorage ? '' : inlineBase64, // Reuse imageBase64 field for voice base64
      voicePath: uploadedToStorage ? voiceStoragePath : '',
      voiceBucket: uploadedToStorage ? uploadedBucket : '',
      voiceDurationMs: durationMs,
      lastMessage: 'Voice note',
      messageId: messageRef.id,
    );
  }

  Future<void> _writeMessage({
    required String doctorId,
    required String patientId,
    required String messageType,
    required String text,
    required String imageUrl,
    required String imagePath,
    required String imageBucket,
    required String imageBase64,
    String voicePath = '',
    String voiceBucket = '',
    int voiceDurationMs = 0,
    required String lastMessage,
    String? messageId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to send messages.');
    }

    await _ensureAccess(doctorId: doctorId, patientId: patientId);

    final senderIsDoctor = user.uid == doctorId;
    final senderName = await _resolveUserName(
      userId: user.uid,
      isDoctor: senderIsDoctor,
      fallback: user.displayName ?? user.email?.split('@').first,
    );
    final doctorName = await _resolveUserName(userId: doctorId, isDoctor: true);
    final patientDoc =
        await _firestore.collection('patients').doc(patientId).get();
    final patientName =
        _extractName(patientDoc.data() ?? <String, dynamic>{}, 'Patient');

    final chatDoc = _chatDoc(doctorId: doctorId, patientId: patientId);
    await chatDoc.set(
      {
        'doctorId': doctorId,
        'doctorName': doctorName,
        'patientId': patientId,
        'patientName': patientName,
        'participants': [doctorId, patientId],
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': lastMessage,
        'lastMessageType': messageType,
      },
      SetOptions(merge: true),
    );

    final doc = messageId == null
        ? _messagesRef(doctorId: doctorId, patientId: patientId).doc()
        : _messagesRef(doctorId: doctorId, patientId: patientId).doc(messageId);

    await doc.set({
      'senderId': user.uid,
      'senderName': senderName,
      'senderRole': senderIsDoctor ? 'doctor' : 'patient',
      'messageType': messageType,
      'text': text,
      'imageUrl': imageUrl,
      'imagePath': imagePath,
      'imageBucket': imageBucket,
      'imageBase64': imageBase64,
      'voicePath': voicePath,
      'voiceBucket': voiceBucket,
      'voiceDurationMs': voiceDurationMs,
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  String _compressAndEncodeInlineImage(List<int> inputBytes) {
    var bytes = List<int>.from(inputBytes);
    final decoded = img.decodeImage(Uint8List.fromList(bytes));

    if (decoded != null) {
      var working = decoded;
      if (working.width > 1280) {
        working = img.copyResize(working, width: 1280);
      }

      for (final quality in const [75, 65, 55, 45]) {
        bytes = img.encodeJpg(working, quality: quality);
        if (bytes.length <= 450 * 1024) break;

        if (working.width > 560) {
          working =
              img.copyResize(working, width: (working.width * 0.8).round());
        }
      }
    }

    if (bytes.length > 700 * 1024) {
      throw StateError(
          'Selected image is too large for chat. Please choose a smaller image.');
    }

    return base64Encode(bytes);
  }

  Future<String> _uploadImageWithBucketFallback({
    required String imagePath,
    required Uint8List imageBytes,
    required String localImagePath,
    required String contentType,
  }) async {
    final candidates = _candidateBuckets();
    FirebaseException? lastError;

    for (final bucket in candidates) {
      final storage =
          FirebaseStorage.instanceFor(bucket: _bucketToGsUrl(bucket));
      final ref = storage.ref().child(imagePath);
      try {
        await ref.putData(
          imageBytes,
          SettableMetadata(contentType: contentType),
        );
        return bucket;
      } on FirebaseException catch (e) {
        lastError = e;
        if (e.code == 'object-not-found') {
          try {
            await ref.putFile(
              File(localImagePath),
              SettableMetadata(contentType: contentType),
            );
            return bucket;
          } on FirebaseException catch (e2) {
            lastError = e2;
          }
        }
        if (e.code == 'unauthorized') rethrow;
      }
    }

    if (lastError != null) throw lastError;
    throw StateError('No valid Firebase Storage bucket was found for upload.');
  }

  List<String> _candidateBuckets() {
    final options = Firebase.app().options;
    final projectId = options.projectId;
    final configured = (options.storageBucket ?? '').trim();
    final buckets = <String>{};

    if (configured.isNotEmpty) {
      buckets.add(_stripBucketPrefix(configured));
    }
    if (projectId.trim().isNotEmpty) {
      buckets.add('$projectId.firebasestorage.app');
      buckets.add('$projectId.appspot.com');
    }

    return buckets.where((b) => b.isNotEmpty).toList(growable: false);
  }

  String _bucketToGsUrl(String bucket) {
    if (bucket.startsWith('gs://')) return bucket;
    return 'gs://$bucket';
  }

  String _stripBucketPrefix(String bucket) {
    if (bucket.startsWith('gs://')) {
      return bucket.substring(5);
    }
    return bucket;
  }

  Future<void> _ensureAccess({
    required String doctorId,
    required String patientId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to access chat.');
    }

    if (user.uid != doctorId && user.uid != patientId) {
      throw StateError('You are not allowed to access this chat.');
    }

    final patientDoc =
        await _firestore.collection('patients').doc(patientId).get();
    if (!patientDoc.exists) {
      throw StateError('Patient record not found.');
    }

    final assignedDoctorId =
        patientDoc.data()?['assignedDoctorId'] as String? ?? '';
    if (assignedDoctorId != doctorId) {
      throw StateError(
          'Chat is allowed only between a patient and the assigned doctor.');
    }
  }

  DocumentReference<Map<String, dynamic>> _chatDoc({
    required String doctorId,
    required String patientId,
  }) {
    return _firestore
        .collection(_collection)
        .doc(chatIdFor(doctorId: doctorId, patientId: patientId));
  }

  CollectionReference<Map<String, dynamic>> _messagesRef({
    required String doctorId,
    required String patientId,
  }) {
    return _chatDoc(doctorId: doctorId, patientId: patientId)
        .collection('messages');
  }

  Future<String> _resolveUserName({
    required String userId,
    required bool isDoctor,
    String? fallback,
  }) async {
    final collection = isDoctor ? 'doctors' : 'patients';
    try {
      final doc = await _firestore.collection(collection).doc(userId).get();
      final data = doc.data();
      if (data != null) {
        final name = _extractName(data, isDoctor ? 'Doctor' : 'Patient');
        if (name.trim().isNotEmpty) return name.trim();
      }
    } catch (_) {}

    if (fallback != null && fallback.trim().isNotEmpty) {
      return fallback.trim();
    }
    return isDoctor ? 'Doctor' : 'Patient';
  }

  static String _extractName(Map<String, dynamic> data, String fallback) {
    final firstName = data['firstName'] as String? ?? '';
    final lastName = data['lastName'] as String? ?? '';
    if (firstName.trim().isNotEmpty && lastName.trim().isNotEmpty) {
      return '$firstName $lastName'.trim();
    }

    final fullName = data['fullName'] as String? ?? '';
    if (fullName.trim().isNotEmpty) {
      return fullName.trim();
    }

    return fallback;
  }

  String _fileExtensionFromPath(String path) {
    final normalized = path.toLowerCase();
    final dot = normalized.lastIndexOf('.');
    if (dot == -1 || dot == normalized.length - 1) return 'jpg';

    final ext = normalized.substring(dot + 1);
    if (ext == 'jpeg' || ext == 'jpg' || ext == 'png' || ext == 'webp') {
      return ext;
    }
    return 'jpg';
  }

  String _contentTypeForExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
