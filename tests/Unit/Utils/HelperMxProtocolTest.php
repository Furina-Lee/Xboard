<?php

namespace Tests\Unit\Utils;

use App\Models\Server;
use App\Services\ServerService;
use App\Utils\Helper;
use Tests\TestCase;

class HelperMxProtocolTest extends TestCase
{
    public function test_mx_uri_contains_mundo_connect_transport_settings(): void
    {
        $uri = Helper::buildMxUri('user-token', [
            'host' => 'example.com',
            'port' => 443,
            'name' => 'Mundo MX',
            'protocol_settings' => [
                'tls' => 1,
                'tls_settings' => [
                    'server_name' => 'edge.example.com',
                    'allow_insecure' => false,
                ],
                'network' => 'mc1',
                'network_settings' => [
                    'path' => '/connect path+1',
                    'host' => 'transport.example.com',
                    'mode' => 'websocket',
                    'cidrSegments' => ['10', '20'],
                ],
            ],
        ]);

        $this->assertStringStartsWith('mx://user-token@example.com:443?', $uri);
        $this->assertStringContainsString('security=tls', $uri);
        $this->assertStringContainsString('type=mc1', $uri);
        $this->assertStringContainsString('sni=edge.example.com', $uri);
        $this->assertStringContainsString('host=transport.example.com', $uri);
        $this->assertStringContainsString('path=%2Fconnect%20path%2B1', $uri);
        $this->assertStringContainsString('mode=websocket', $uri);
        $this->assertStringContainsString('cidr=10%2C20', $uri);
        $this->assertStringContainsString('#Mundo%20MX', $uri);
    }

    public function test_mx_mc1_uri_includes_host_path_and_sni_when_settings_are_empty(): void
    {
        $uri = Helper::buildMxUri('user-token', [
            'host' => 'edge.example.com',
            'port' => 443,
            'name' => 'MX',
            'protocol_settings' => [
                'network' => 'mc1',
                'network_settings' => ['host' => '', 'path' => ''],
            ],
        ]);

        parse_str(parse_url($uri, PHP_URL_QUERY), $query);
        $this->assertSame('edge.example.com', $query['sni']);
        $this->assertSame('edge.example.com', $query['host']);
        $this->assertSame('/', $query['path']);
    }

    public function test_mx_rdp_uri_encodes_username(): void
    {
        $uri = Helper::buildMxUri('user-token', [
            'host' => '2001:db8::42',
            'port' => 443,
            'name' => 'RDP',
            'protocol_settings' => [
                'network' => 'mundordp',
                'network_settings' => ['username' => 'RDP User+1'],
            ],
        ]);

        $this->assertStringStartsWith('mx://user-token@[2001:db8::42]:443?', $uri);
        $this->assertStringContainsString('type=mundordp', $uri);
        $this->assertStringContainsString('username=RDP%20User%2B1', $uri);
    }

    public function test_mx_uri_prefers_tls_allow_insecure_and_supports_the_legacy_setting(): void
    {
        $cases = [
            ['allow_insecure' => false, 'tls_settings' => ['allow_insecure' => true]],
            ['allow_insecure' => true, 'tls_settings' => ['allow_insecure' => false]],
            ['allow_insecure' => true],
            [],
        ];

        foreach ($cases as $index => $settings) {
            $uri = Helper::buildMxUri('user-token', [
                'host' => 'edge.example.com',
                'port' => 443,
                'name' => 'MX',
                'protocol_settings' => $settings + ['tls' => 1, 'network' => 'mundordp'],
            ]);

            parse_str(parse_url($uri, PHP_URL_QUERY), $query);
            $this->assertSame(in_array($index, [0, 2], true) ? '1' : null, $query['allowInsecure'] ?? null);
        }
    }

    public function test_mx_server_config_only_sends_private_keys_for_explicit_reality_modes(): void
    {
        foreach ([[0, 'mc1', false], [1, 'mc1', false], [2, 'mc1', true], [1, 'mimundoreal', true]] as [$tls, $network, $sendKey]) {
            $node = new Server();
            $node->forceFill([
                'type' => 'mx',
                'host' => 'edge.example.com',
                'server_port' => 21411,
                'protocol_settings' => [
                    'tls' => $tls,
                    'network' => $network,
                    'tls_settings' => [
                        'server_name' => 'edge.example.com',
                        'private_key' => 'example-reality-key',
                    ],
                ],
            ]);

            $config = ServerService::buildNodeConfig($node);
            $this->assertSame('edge.example.com', $config['tls_settings']['server_name']);
            if ($sendKey) {
                $this->assertSame('example-reality-key', $config['tls_settings']['private_key']);
            } else {
                $this->assertArrayNotHasKey('private_key', $config['tls_settings']);
            }
        }
    }

    public function test_mc1_defaults_follow_sni_and_keep_existing_paths_on_save(): void
    {
        $fresh = Helper::withMc1Defaults(['tls_settings' => ['server_name' => 'edge.example.com']]);
        $transport = $fresh['network_settings'];

        $this->assertSame('edge.example.com', $transport['host']);
        $this->assertSame('auto', $transport['mode']);
        $this->assertMatchesRegularExpression('/^\/[0-9a-f]{16}$/', $transport['path']);
        $this->assertSame($fresh, Helper::withMc1Defaults($fresh));
        $this->assertNotSame($transport['path'], Helper::withMc1Defaults($fresh, newPath: true)['network_settings']['path']);

        $random = Helper::withMc1Defaults(['network_settings' => ['host' => 'custom.example', 'path' => '/keep']]);
        $this->assertMatchesRegularExpression('/^mx-[0-9a-f]{12}\.example$/', $random['tls_settings']['server_name']);
        $this->assertSame('custom.example', $random['network_settings']['host']);
        $this->assertSame('/keep', $random['network_settings']['path']);
    }

    public function test_mundo_rdp_transport_defaults_username_and_casts_boolean_values(): void
    {
        $config = [];
        Helper::configureMundoRdpSettings([
            'acceptProxyProtocol' => 'true',
            'useTLSCertificate' => 0,
            'fakeTitle' => 'Mundo RDP',
        ], $config);

        $this->assertSame('MundoUser', $config['username']);
        $this->assertTrue($config['acceptProxyProtocol']);
        $this->assertFalse($config['useTLSCertificate']);
        $this->assertSame('Mundo RDP', $config['fakeTitle']);
    }
}
