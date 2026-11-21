#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include "flutter/generated_plugin_registrant.h"

static void activate(GtkApplication* app, gpointer) {
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(app));
  gtk_window_set_title(window, "musAni");
  gtk_window_set_default_size(window, 960, 640);
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  FlView* view = fl_view_new(project);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  gtk_widget_show_all(GTK_WIDGET(window));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

int main(int argc, char** argv) {
  g_autoptr(GtkApplication) app = gtk_application_new(
      APPLICATION_ID, G_APPLICATION_NON_UNIQUE);
  g_signal_connect(app, "activate", G_CALLBACK(activate), nullptr);
  return g_application_run(G_APPLICATION(app), argc, argv);
}
