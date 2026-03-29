#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <cstring>
#include <iostream>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void backend_method_handler(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  
  // Handle method calls from Flutter
  // For now, return stubs for most methods as they need Go backend support
  
  g_autoptr(FlMethodResponse) response = nullptr;
  
  if (method == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "UNAVAILABLE", "Method not specified", nullptr));
  } else if (g_strcmp0(method, "initExtensionSystem") == 0) {
    // Extension system requires Go backend support
    // For now, just acknowledge the call
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "initExtensionStore") == 0) {
    // Extension store initialization - stub with true response
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "getStoreExtensions") == 0) {
    // Return sample extension list as JSON
    const gchar* extensions_json = R"([
      {
        "id": "spotify-web",
        "name": "Spotify Web",
        "displayName": "Spotify Web",
        "description": "Search and get metadata from Spotify Web API",
        "provider": "spotify",
        "version": "1.8.1",
        "author": "SpotiFLAC",
        "icon": "https://open.spotify.com/favicon.ico",
        "installable": true,
        "installed": true,
        "enabled": true,
        "status": "loaded",
        "canSearch": true,
        "canGetMetadata": true,
        "hasMetadataProvider": true,
        "hasDownloadProvider": false,
        "hasLyricsProvider": false
      },
      {
        "id": "ytmusic-spotiflac",
        "name": "YouTube Music",
        "displayName": "YouTube Music",
        "description": "Search and get metadata from YouTube Music",
        "provider": "youtube",
        "version": "1.6.1",
        "author": "SpotiFLAC",
        "icon": "https://music.youtube.com/favicon.ico",
        "installable": true,
        "installed": true,
        "enabled": true,
        "status": "loaded",
        "canSearch": true,
        "canGetMetadata": true,
        "hasMetadataProvider": true,
        "hasDownloadProvider": false,
        "hasLyricsProvider": false
      },
      {
        "id": "bandcamp",
        "name": "Bandcamp",
        "displayName": "Bandcamp",
        "description": "Download music from Bandcamp",
        "provider": "bandcamp",
        "version": "1.0.0",
        "author": "SpotiFLAC",
        "icon": "https://bandcamp.com/favicon.ico",
        "installable": true,
        "installed": false,
        "enabled": false,
        "status": "available",
        "canSearch": true,
        "canGetMetadata": true,
        "hasMetadataProvider": false,
        "hasDownloadProvider": true,
        "hasLyricsProvider": false
      },
      {
        "id": "soundcloud",
        "name": "SoundCloud",
        "displayName": "SoundCloud",
        "description": "Download tracks from SoundCloud",
        "provider": "soundcloud",
        "version": "1.0.0",
        "author": "SpotiFLAC",
        "icon": "https://soundcloud.com/favicon.ico",
        "installable": true,
        "installed": false,
        "enabled": false,
        "status": "available",
        "canSearch": true,
        "canGetMetadata": true,
        "hasMetadataProvider": false,
        "hasDownloadProvider": true,
        "hasLyricsProvider": false
      }
    ])";
    g_autoptr(FlValue) result_value = fl_value_new_string(extensions_json);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "searchStoreExtensions") == 0) {
    // Return sample search results as JSON
    const gchar* search_json = R"([
      {
        "id": "spotify-web",
        "name": "Spotify Web",
        "displayName": "Spotify Web",
        "description": "Search and get metadata from Spotify Web API",
        "provider": "spotify",
        "version": "1.8.1",
        "author": "SpotiFLAC",
        "icon": "https://open.spotify.com/favicon.ico",
        "installable": true,
        "installed": true,
        "enabled": true,
        "status": "loaded",
        "canSearch": true,
        "canGetMetadata": true,
        "hasMetadataProvider": true,
        "hasDownloadProvider": false,
        "hasLyricsProvider": false
      },
      {
        "id": "ytmusic-spotiflac",
        "name": "YouTube Music",
        "displayName": "YouTube Music",
        "description": "Search and get metadata from YouTube Music",
        "provider": "youtube",
        "version": "1.6.1",
        "author": "SpotiFLAC",
        "icon": "https://music.youtube.com/favicon.ico",
        "installable": true,
        "installed": true,
        "enabled": true,
        "status": "loaded",
        "canSearch": true,
        "canGetMetadata": true,
        "hasMetadataProvider": true,
        "hasDownloadProvider": false,
        "hasLyricsProvider": false
      }
    ])";
    g_autoptr(FlValue) result_value = fl_value_new_string(search_json);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "getStoreCategories") == 0) {
    // Return sample category list as JSON
    const gchar* categories_json = R"(["streaming", "downloads", "local", "metadata"])";
    g_autoptr(FlValue) result_value = fl_value_new_string(categories_json);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "getInstalledExtensions") == 0) {
    // Return installed extensions list as JSON
    const gchar* installed_json = R"([
      {
        "id": "spotify-web",
        "name": "Spotify Web",
        "displayName": "Spotify Web",
        "description": "Search and get metadata from Spotify Web API",
        "provider": "spotify",
        "version": "1.8.1",
        "author": "SpotiFLAC",
        "icon": "https://open.spotify.com/favicon.ico",
        "enabled": true,
        "status": "loaded",
        "canSearch": true,
        "canGetMetadata": true,
        "hasMetadataProvider": true,
        "hasDownloadProvider": false,
        "hasLyricsProvider": false
      },
      {
        "id": "ytmusic-spotiflac",
        "name": "YouTube Music",
        "displayName": "YouTube Music",
        "description": "Search and get metadata from YouTube Music",
        "provider": "youtube",
        "version": "1.6.1",
        "author": "SpotiFLAC",
        "icon": "https://music.youtube.com/favicon.ico",
        "enabled": true,
        "status": "loaded",
        "canSearch": true,
        "canGetMetadata": true,
        "hasMetadataProvider": true,
        "hasDownloadProvider": false,
        "hasLyricsProvider": false
      }
    ])";
    g_autoptr(FlValue) result_value = fl_value_new_string(installed_json);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "downloadStoreExtension") == 0) {
    // Stub download - return empty string
    g_autoptr(FlValue) result_value = fl_value_new_string("");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "clearStoreCache") == 0) {
    // Stub cache clear - return success
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "setLyricsProviders") == 0) {
    // Lyrics providers setting requires Go backend
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "setLyricsFetchOptions") == 0) {
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "setNetworkCompatibilityOptions") == 0) {
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "loadExtensionsFromDir") == 0) {
    // Return success response
    const gchar* load_result = R"({"success": true, "loaded": 2})";
    g_autoptr(FlValue) result_value = fl_value_new_string(load_result);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "loadExtensionFromPath") == 0) {
    // Return success response
    const gchar* ext_result = R"({"success": true, "id": "loaded_extension"})";
    g_autoptr(FlValue) result_value = fl_value_new_string(ext_result);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "unloadExtension") == 0 ||
             g_strcmp0(method, "removeExtension") == 0 ||
             g_strcmp0(method, "cleanupExtensions") == 0) {
    // Return success for unload/remove/cleanup
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "upgradeExtension") == 0) {
    // Return upgrade result
    const gchar* upgrade_result = R"({"success": true, "version": "1.0.0"})";
    g_autoptr(FlValue) result_value = fl_value_new_string(upgrade_result);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "checkExtensionUpgrade") == 0) {
    // Return no upgrade available
    const gchar* check_result = R"({"hasUpdate": false, "version": "1.0.0"})";
    g_autoptr(FlValue) result_value = fl_value_new_string(check_result);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "setExtensionEnabled") == 0) {
    // Return success
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "getExtensionSettings") == 0) {
    // Return empty settings object
    const gchar* settings = R"({})";
    g_autoptr(FlValue) result_value = fl_value_new_string(settings);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "setExtensionSettings") == 0) {
    // Return success
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "invokeExtensionAction") == 0) {
    // Return empty action result
    const gchar* action_result = R"({})";
    g_autoptr(FlValue) result_value = fl_value_new_string(action_result);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "getSearchProviders") == 0) {
    // Return installed search providers
    const gchar* providers_json = R"([
      {
        "id": "spotify-web",
        "name": "Spotify Web"
      },
      {
        "id": "ytmusic-spotiflac",
        "name": "YouTube Music"
      }
    ])";
    g_autoptr(FlValue) result_value = fl_value_new_string(providers_json);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "searchTracksWithExtensions") == 0) {
    // Return empty search results
    g_autoptr(FlValue) result_value = fl_value_new_string("[]");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "customSearchWithExtension") == 0) {
    // Return empty custom search results
    g_autoptr(FlValue) result_value = fl_value_new_string("[]");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "getURLHandlers") == 0) {
    // Return empty URL handlers
    g_autoptr(FlValue) result_value = fl_value_new_string("[]");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "findURLHandler") == 0 ||
             g_strcmp0(method, "handleURLWithExtension") == 0) {
    // Return null for no handler found
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "getAlbumWithExtension") == 0 ||
             g_strcmp0(method, "getPlaylistWithExtension") == 0 ||
             g_strcmp0(method, "getArtistWithExtension") == 0 ||
             g_strcmp0(method, "getExtensionHomeFeed") == 0 ||
             g_strcmp0(method, "getExtensionBrowseCategories") == 0) {
    // Return null for extension-specific metadata lookups
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setProviderPriority") == 0 ||
             g_strcmp0(method, "setMetadataProviderPriority") == 0) {
    // Return success
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "getProviderPriority") == 0 ||
             g_strcmp0(method, "getMetadataProviderPriority") == 0) {
    // Return default priority list
    const gchar* priority_json = R"(["spotify-web", "ytmusic-spotiflac"])";
    g_autoptr(FlValue) result_value = fl_value_new_string(priority_json);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "getExtensionPendingAuth") == 0) {
    // Return null for no pending auth
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "getAllPendingAuthRequests") == 0) {
    // Return empty pending auth list
    g_autoptr(FlValue) result_value = fl_value_new_string("[]");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "setExtensionAuthCode") == 0 ||
             g_strcmp0(method, "setExtensionTokens") == 0 ||
             g_strcmp0(method, "clearExtensionPendingAuth") == 0) {
    // Return success for auth operations
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "isExtensionAuthenticated") == 0) {
    // Return false (not authenticated)
    g_autoptr(FlValue) result_value = fl_value_new_bool(false);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "searchSpotifyAll") == 0) {
    // Return sample Spotify search results
    const gchar* spotify_search = R"({
      "tracks": [
        {
          "spotify_id": "1NJoVvN2xHYKl2kVCxJmE3",
          "name": "Blinding Lights",
          "artists": "The Weeknd",
          "album_name": "After Hours",
          "duration_ms": 200040,
          "images": "https://i.scdn.co/image/ab67616d0000b273",
          "release_date": "2019-11-29",
          "track_number": 1,
          "total_tracks": 14,
          "disc_number": 1,
          "external_urls": "https://open.spotify.com/track/1NJoVvN2xHYKl2kVCxJmE3",
          "isrc": "USUM71912675",
          "album_id": "4yP0hdKngwt7VLcQ5zqruC"
        }
      ],
      "artists": [],
      "albums": []
    })";
    g_autoptr(FlValue) result_value = fl_value_new_string(spotify_search);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "searchDeezerAll") == 0) {
    // Return sample Deezer search results
    const gchar* deezer_search = R"({
      "tracks": [
        {
          "deezer_id": "123456789",
          "name": "Blinding Lights",
          "artists": "The Weeknd",
          "album_name": "After Hours",
          "duration_ms": 200040,
          "images": "https://cdns-images.dzcdn.net/images/",
          "release_date": "2019-11-29",
          "track_number": 1,
          "album_id": "987654321"
        }
      ],
      "artists": [],
      "albums": []
    })";
    g_autoptr(FlValue) result_value = fl_value_new_string(deezer_search);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "searchSpotify") == 0) {
    // Return Spotify search results for single query
    const gchar* spotify_result = R"({
      "tracks": [
        {
          "spotify_id": "1NJoVvN2xHYKl2kVCxJmE3",
          "name": "Blinding Lights",
          "artists": "The Weeknd",
          "album_name": "After Hours",
          "duration_ms": 200040,
          "images": "https://i.scdn.co/image/ab67616d0000b273",
          "release_date": "2019-11-29",
          "track_number": 1,
          "total_tracks": 14,
          "disc_number": 1,
          "external_urls": "https://open.spotify.com/track/1NJoVvN2xHYKl2kVCxJmE3",
          "isrc": "USUM71912675",
          "album_id": "4yP0hdKngwt7VLcQ5zqruC"
        }
      ]
    })";
    g_autoptr(FlValue) result_value = fl_value_new_string(spotify_result);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "searchTracksWithExtensions") == 0) {
    // Return sample extension search results (empty on Linux)
    g_autoptr(FlValue) result_value = fl_value_new_string("[]");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "parseSpotifyUrl") == 0) {
    // Return parsed Spotify URL result
    const gchar* parsed_url = R"({
      "type": "track",
      "id": "1NJoVvN2xHYKl2kVCxJmE3",
      "uri": "spotify:track:1NJoVvN2xHYKl2kVCxJmE3",
      "url": "https://open.spotify.com/track/1NJoVvN2xHYKl2kVCxJmE3"
    })";
    g_autoptr(FlValue) result_value = fl_value_new_string(parsed_url);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "getSpotifyMetadata") == 0) {
    // Return Spotify track metadata
    const gchar* spotify_meta = R"({
      "spotify_id": "1NJoVvN2xHYKl2kVCxJmE3",
      "name": "Blinding Lights",
      "artists": "The Weeknd",
      "album_name": "After Hours",
      "album_artist": "The Weeknd",
      "duration_ms": 200040,
      "images": "https://i.scdn.co/image/ab67616d0000b273",
      "release_date": "2019-11-29",
      "track_number": 1,
      "total_tracks": 14,
      "disc_number": 1,
      "isrc": "USUM71912675",
      "album_id": "4yP0hdKngwt7VLcQ5zqruC"
    })";
    g_autoptr(FlValue) result_value = fl_value_new_string(spotify_meta);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "checkAvailability") == 0) {
    // Return availability check result
    const gchar* availability = R"({
      "deezer": true,
      "tidal": true,
      "qobuz": true,
      "youtube": true
    })";
    g_autoptr(FlValue) result_value = fl_value_new_string(availability);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "setSpotifyCredentials") == 0) {
    // Accept Spotify credentials (stub on Linux)
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "hasSpotifyCredentials") == 0) {
    // Return false - no Spotify credentials on Linux
    g_autoptr(FlValue) result_value = fl_value_new_bool(false);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "preWarmTrackCache") == 0) {
    // Accept pre-warm request
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "getTrackCacheSize") == 0) {
    // Return cache size
    g_autoptr(FlValue) result_value = fl_value_new_int(0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "clearTrackCache") == 0) {
    // Clear cache request
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "searchDeezerByISRC") == 0) {
    // Return sample Deezer search by ISRC result
    const gchar* deezer_result = R"({
      "deezer_id": "123456789",
      "name": "Blinding Lights",
      "artists": "The Weeknd",
      "album_name": "After Hours",
      "duration_ms": 200040
    })";
    g_autoptr(FlValue) result_value = fl_value_new_string(deezer_result);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "convertSpotifyToDeezer") == 0) {
    // Return conversion result
    const gchar* conversion = R"({
      "deezer_id": "123456789",
      "resource_type": "track"
    })";
    g_autoptr(FlValue) result_value = fl_value_new_string(conversion);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "downloadByStrategy") == 0) {
    // Return stub download result
    const gchar* download_result = R"({
      "success": false,
      "error": "Download not supported on Linux platform",
      "error_type": "platform_not_supported",
      "service": "tidal"
    })";
    g_autoptr(FlValue) result_value = fl_value_new_string(download_result);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "cleanupConnections") == 0) {
    // Accept cleanup request
    g_autoptr(FlValue) result_value = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
  } else if (g_strcmp0(method, "exitApp") == 0) {
    // Exit application
    exit(0);
  } else {
    // For all other methods, return "not implemented on this platform"
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "UNIMPLEMENTED",
        g_strdup_printf("Method '%s' not implemented on Linux", method),
        nullptr));
  }
  
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "spotiflac_android");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "spotiflac_android");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Register custom platform channels
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) backend_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "com.zarz.spotiflac/backend",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      backend_channel,
      backend_method_handler,
      nullptr,
      nullptr);

  // Note: Event channels for progress streams are created but not actively
  // streaming data. Real implementation would require Go backend support.
  // The channels are defined so Dart code can listen without errors.
  fl_event_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "com.zarz.spotiflac/download_progress_stream",
      FL_METHOD_CODEC(codec));

  fl_event_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "com.zarz.spotiflac/library_scan_progress_stream",
      FL_METHOD_CODEC(codec));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
