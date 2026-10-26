<?php

namespace Tests\Unit\Utils;

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
                    'path' => '/connect',
                    'host' => 'transport.example.com',
                    'mode' => 'websocket',
                    'cidrSegments' => ['10', '20'],
                ],
            ],
        ]);

        $this->assertStringStartsWith('mx://user-token@example.com:443?', $uri);
        $this->assertStringContainsString('security=tls', $uri);
        $this->assertStringContainsString('type=mc1', $uri);
        $this->assertStringContainsString('mode=websocket', $uri);
        $this->assertStringContainsString('cidr=10%2C20', $uri);
        $this->assertStringContainsString('#Mundo%20MX', $uri);
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
