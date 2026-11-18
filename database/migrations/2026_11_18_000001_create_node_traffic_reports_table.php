<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('node_traffic_reports', function (Blueprint $table) {
            $table->unsignedBigInteger('node_id');
            $table->char('report_id', 32);
            $table->unsignedBigInteger('received_at')->index();
            $table->primary(['node_id', 'report_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('node_traffic_reports');
    }
};
