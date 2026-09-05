// Minimal headless WPF stubs used by the copied parser sources.
using System;
using System.Collections;
using System.Collections.Generic;

namespace FFXI_Navmesh_Builder.Views
{
    public sealed class HomeView
    {
        public HomeView()
        {
            RtbDebug = new System.Windows.Controls.ListBox();
        }

        public System.Windows.Controls.ListBox RtbDebug { get; }
    }
}

namespace System.Windows.Controls
{
    public sealed class ListBox
    {
        public ListBox()
        {
            Items = new List<object>();
        }

        public Dispatcher Dispatcher { get; } = new();
        public IList Items { get; }
        public int SelectedIndex { get; set; } = -1;
        public object SelectedItem => SelectedIndex >= 0 && SelectedIndex < Items.Count ? Items[SelectedIndex] : null;

        public void ScrollIntoView(object item)
        {
        }
    }

    public sealed class Dispatcher
    {
        public void Invoke(Action action)
        {
            action?.Invoke();
        }
    }
}
