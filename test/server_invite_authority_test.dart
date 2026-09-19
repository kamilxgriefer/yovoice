import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_invite_authority.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';

Server server({
  required ServerType type,
  required ServerPrivacy privacy,
  bool legacy = false,
}) => Server(
  id: 's',
  name: 'Po godzinach',
  description: '',
  ownerId: 'owner',
  type: type,
  privacy: privacy,
  schemaVersion: legacy ? null : 1,
  activationState: legacy ? null : 'active',
);

void main() {
  group('serverAdmitsPublicJoin', () {
    test('is true for exactly the two templates that may be public', () {
      for (final type in ServerType.values) {
        expect(
          serverAdmitsPublicJoin(
            server(type: type, privacy: ServerPrivacy.public),
          ),
          type == ServerType.community || type == ServerType.podcast,
          reason: '$type',
        );
      }
    });

    test('private and inviteOnly are both "not publicly joinable"', () {
      for (final privacy in [ServerPrivacy.private, ServerPrivacy.inviteOnly]) {
        expect(
          serverAdmitsPublicJoin(
            server(type: ServerType.community, privacy: privacy),
          ),
          isFalse,
          reason: '$privacy',
        );
      }
    });

    test('a legacy root carries no V1 privacy authority', () {
      expect(
        serverAdmitsPublicJoin(
          server(
            type: ServerType.community,
            privacy: ServerPrivacy.public,
            legacy: true,
          ),
        ),
        isFalse,
      );
    });
  });

  group('canInviteToServer', () {
    test('an unknown role withholds the affordance', () {
      expect(
        canInviteToServer(
          server(type: ServerType.community, privacy: ServerPrivacy.public),
          null,
        ),
        isFalse,
      );
    });

    test('the moderator roles may invite on every server', () {
      const moderators = [
        ServerMemberRole.owner,
        ServerMemberRole.coOwner,
        ServerMemberRole.admin,
        ServerMemberRole.moderator,
      ];
      for (final role in moderators) {
        for (final type in ServerType.values) {
          for (final privacy in ServerPrivacy.values) {
            if (type == ServerType.family &&
                privacy != ServerPrivacy.inviteOnly) {
              continue;
            }
            if (!type.allowsPublic && privacy == ServerPrivacy.public) continue;
            expect(
              canInviteToServer(server(type: type, privacy: privacy), role),
              isTrue,
              reason: '$role on $type/$privacy',
            );
          }
        }
      }
    });

    test('a member may invite exactly where anyone may already join', () {
      for (final type in ServerType.values) {
        for (final privacy in ServerPrivacy.values) {
          if (type == ServerType.family &&
              privacy != ServerPrivacy.inviteOnly) {
            continue;
          }
          if (!type.allowsPublic && privacy == ServerPrivacy.public) continue;
          expect(
            canInviteToServer(
              server(type: type, privacy: privacy),
              ServerMemberRole.member,
            ),
            type.allowsPublic && privacy == ServerPrivacy.public,
            reason: '$type/$privacy',
          );
        }
      }
    });

    test('a guest never invites — demotion stays a control', () {
      expect(
        canInviteToServer(
          server(type: ServerType.community, privacy: ServerPrivacy.public),
          ServerMemberRole.guest,
        ),
        isFalse,
      );
      expect(
        canInviteToServer(
          server(type: ServerType.friends, privacy: ServerPrivacy.inviteOnly),
          ServerMemberRole.guest,
        ),
        isFalse,
      );
    });

    test('a member of a legacy public club is not widened', () {
      expect(
        canInviteToServer(
          server(
            type: ServerType.community,
            privacy: ServerPrivacy.public,
            legacy: true,
          ),
          ServerMemberRole.member,
        ),
        isFalse,
      );
      // …while a legacy moderator keeps exactly the affordance they have today.
      expect(
        canInviteToServer(
          server(
            type: ServerType.community,
            privacy: ServerPrivacy.public,
            legacy: true,
          ),
          ServerMemberRole.moderator,
        ),
        isTrue,
      );
    });
  });
}
