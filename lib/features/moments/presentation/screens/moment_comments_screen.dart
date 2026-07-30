import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';

class MomentCommentsScreen extends StatefulWidget {
  const MomentCommentsScreen({required this.moment, super.key});

  final VoiceMoment moment;

  @override
  State<MomentCommentsScreen> createState() => _MomentCommentsScreenState();
}

class _MomentCommentsScreenState extends State<MomentCommentsScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF14101D);
  static const _border = Color(0xFF352642);
  static const _muted = Color(0xFFA79DAF);
  static const _primary = Color(0xFFA51FFF);

  final TextEditingController _controller = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _sending = false;

  CollectionReference<Map<String, dynamic>> get _comments => _firestore
      .collection('voiceMoments')
      .doc(widget.moment.id)
      .collection('comments');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _controller.text.trim();
    final user = _auth.currentUser;
    if (text.isEmpty || user == null || _sending) return;

    setState(() => _sending = true);
    try {
      final userSnapshot = await _firestore.collection('users').doc(user.uid).get();
      final userData = userSnapshot.data();
      final displayName = (userData?['displayName'] as String?)?.trim();
      final photoUrl = userData?['photoUrl'] as String?;
      final commentReference = _comments.doc();
      final momentReference = _firestore.collection('voiceMoments').doc(widget.moment.id);
      final batch = _firestore.batch();

      batch.set(commentReference, {
        'type': 'text',
        'authorId': user.uid,
        'authorName': displayName?.isNotEmpty == true
            ? displayName
            : user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : user.email?.split('@').first ?? 'YoVoice user',
        'authorPhotoUrl': photoUrl ?? user.photoURL,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(momentReference, {
        'commentCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      _controller.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not post comment: $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text('Comments'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _comments.orderBy('createdAt', descending: false).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Could not load comments.', style: TextStyle(color: _muted)));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final comments = snapshot.data!.docs;
                  if (comments.isEmpty) {
                    return const Center(child: Text('Be the first to comment.', style: TextStyle(color: _muted)));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: comments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final data = comments[index].data();
                      final name = data['authorName'] as String? ?? 'YoVoice user';
                      final photo = data['authorPhotoUrl'] as String?;
                      final type = data['type'] as String? ?? 'text';
                      return _CommentCard(name: name, photo: photo, data: data, isVoice: type == 'voice');
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: const BoxDecoration(color: _surface, border: Border(top: BorderSide(color: _border))),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendComment(),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Write a comment...',
                        hintStyle: const TextStyle(color: _muted),
                        filled: true,
                        fillColor: _background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendComment,
                    style: IconButton.styleFrom(backgroundColor: _primary),
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentCard extends StatefulWidget {
  const _CommentCard({required this.name, required this.photo, required this.data, required this.isVoice});
  final String name;
  final String? photo;
  final Map<String, dynamic> data;
  final bool isVoice;

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.data['audioUrl'] as String?;
    if (url == null || url.isEmpty) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(url));
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.data['text'] as String? ?? '';
    final duration = widget.data['durationSeconds'] as int? ?? 0;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _MomentCommentsScreenState._surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _MomentCommentsScreenState._border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _MomentCommentsScreenState._primary,
            backgroundImage: widget.photo?.isNotEmpty == true ? NetworkImage(widget.photo!) : null,
            child: widget.photo?.isNotEmpty == true ? null : Text(widget.name.isNotEmpty ? widget.name[0].toUpperCase() : 'Y'),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                if (widget.isVoice) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _toggle,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF271335),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Voice reply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                          Text('0:${duration.toString().padLeft(2, '0')}', style: const TextStyle(color: _MomentCommentsScreenState._muted)),
                        ],
                      ),
                    ),
                  ),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(text, style: const TextStyle(color: Colors.white70)),
                  ],
                ] else ...[
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(color: Colors.white, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
