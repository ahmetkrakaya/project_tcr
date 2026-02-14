import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Supabase Database Provider
final supabaseDatabaseProvider = Provider<SupabaseQueryBuilder>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.from('');
});

/// Supabase Storage Provider
final supabaseStorageProvider = Provider<SupabaseStorageClient>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.storage;
});

/// Supabase Realtime Provider
final supabaseRealtimeProvider = Provider<RealtimeClient>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.realtime;
});

/// Storage Bucket Providers
final avatarsBucketProvider = Provider<StorageFileApi>((ref) {
  final storage = ref.watch(supabaseStorageProvider);
  return storage.from('avatars');
});

final eventPhotosBucketProvider = Provider<StorageFileApi>((ref) {
  final storage = ref.watch(supabaseStorageProvider);
  return storage.from('event-photos');
});

final routesBucketProvider = Provider<StorageFileApi>((ref) {
  final storage = ref.watch(supabaseStorageProvider);
  return storage.from('routes');
});

final listingImagesBucketProvider = Provider<StorageFileApi>((ref) {
  final storage = ref.watch(supabaseStorageProvider);
  return storage.from('listing-images');
});

final chatImagesBucketProvider = Provider<StorageFileApi>((ref) {
  final storage = ref.watch(supabaseStorageProvider);
  return storage.from('chat-images');
});
