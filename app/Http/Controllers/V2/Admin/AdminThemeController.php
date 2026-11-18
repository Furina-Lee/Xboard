<?php

namespace App\Http\Controllers\V2\Admin;

use App\Http\Controllers\Controller;
use App\Services\AdminThemeService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class AdminThemeController extends Controller
{
    public function index(AdminThemeService $themes)
    {
        return response()->json(['themes' => $themes->ids(), 'selected' => $themes->selected()]);
    }

    public function select(Request $request, AdminThemeService $themes)
    {
        $data = $request->validate(['id' => ['required', 'string', Rule::in($themes->ids())]]);
        admin_setting(['admin_theme_selected' => $data['id']]);

        return $this->index($themes);
    }

    public function upload(Request $request, AdminThemeService $themes)
    {
        $data = $request->validate([
            'theme' => ['required', 'file', 'extensions:json', 'max:4'],
        ]);
        $themes->upload($data['theme']->get());

        return $this->index($themes);
    }
}
