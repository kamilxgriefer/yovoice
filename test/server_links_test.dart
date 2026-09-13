import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/servers/data/server_links.dart';

void main() {
  group('canonical Server links', () {
    test('builds and parses a server destination', () {
      final uri = buildServerLink('srv_123');

      expect(uri.toString(), 'https://app.yovoice.app/?server=srv_123');
      expect(parseServerLink(uri), const ServerLinkTarget(serverId: 'srv_123'));
    });

    test('keeps an optional channel destination', () {
      final uri = buildServerLink('srv_123', channelId: 'stage_live');

      expect(
        uri.toString(),
        'https://app.yovoice.app/?server=srv_123&channel=stage_live',
      );
      expect(
        parseServerLink(uri),
        const ServerLinkTarget(serverId: 'srv_123', channelId: 'stage_live'),
      );
    });

    test('rejects malformed identifiers when building', () {
      expect(() => buildServerLink('../private'), throwsArgumentError);
      expect(
        () => buildServerLink('server', channelId: 'channel/other'),
        throwsArgumentError,
      );
    });

    test('fails closed for altered public contracts', () {
      for (final uri in <Uri>[
        Uri.parse('http://app.yovoice.app/?server=srv_123'),
        Uri.parse('https://yovoice.app/?server=srv_123'),
        Uri.parse('https://app.yovoice.app/path?server=srv_123'),
        Uri.parse('https://app.yovoice.app/?server=srv_123&extra=1'),
        Uri.parse('https://app.yovoice.app/?server=srv_123#fragment'),
        Uri.parse('https://app.yovoice.app/?server=srv_123&server=other'),
        Uri.parse('https://user@app.yovoice.app/?server=srv_123'),
        Uri.parse('https://app.yovoice.app:444/?server=srv_123'),
        Uri.parse('https://app.yovoice.app/?server=../private'),
        Uri.parse('https://app.yovoice.app/?channel=general'),
      ]) {
        expect(parseServerLink(uri), isNull, reason: uri.toString());
      }
    });
  });

  group('legacy Club links', () {
    test('resolve only a safe Club id for the Server facade', () {
      expect(
        parseLegacyClubServerLink(
          Uri.parse('https://yovoice.app/?club=community_1'),
        ),
        'community_1',
      );
      expect(
        parseLegacyClubServerLink(
          Uri.parse('https://app.yovoice.app/?club=community_1'),
        ),
        'community_1',
      );
    });

    test('rejects ambiguous or unsafe legacy links', () {
      for (final uri in <Uri>[
        Uri.parse('https://example.com/?club=community_1'),
        Uri.parse('https://yovoice.app/?club=community_1&server=other'),
        Uri.parse('https://yovoice.app/?club=../private'),
        Uri.parse('https://yovoice.app/clubs/community_1'),
      ]) {
        expect(parseLegacyClubServerLink(uri), isNull, reason: uri.toString());
      }
    });
  });

  group('cold-start Server destination', () {
    test('canonical link builds the real workspace and preserves channel', () {
      final target = parseInitialServerWorkspaceLink(
        Uri.parse('https://app.yovoice.app/?server=srv_123&channel=stage_live'),
      );

      expect(target, isNotNull);
      final destination = serverWorkspaceForInitialLink(target!);
      expect(destination.serverId, 'srv_123');
      expect(destination.initialChannelId, 'stage_live');
      expect(destination.isRootTab, isFalse);
    });

    test('legacy Club link builds the same workspace facade', () {
      final target = parseInitialServerWorkspaceLink(
        Uri.parse('https://yovoice.app/?club=community_1'),
      );

      expect(target, const ServerLinkTarget(serverId: 'community_1'));
      expect(serverWorkspaceForInitialLink(target!).serverId, 'community_1');
    });
  });
}
