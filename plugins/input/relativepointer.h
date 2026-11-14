#pragma once

// Exposes zwp_relative_pointer_v1 motion to QML.
//
// Once the compositor clamps the cursor at a screen edge, absolute pointer
// motion stops, but relative motion keeps arriving. Ambxst uses that to tell a
// deliberate push against the edge from the cursor merely passing by.

#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QtQml/qqmlregistration.h>
#include <QtWaylandClient/QWaylandClientExtensionTemplate>

#include <memory>

#include "qwayland-relative-pointer-unstable-v1.h"

struct wl_pointer;

class RelativePointerManager
    : public QWaylandClientExtensionTemplate<RelativePointerManager,
                                             &QtWayland::zwp_relative_pointer_manager_v1::destroy>,
      public QtWayland::zwp_relative_pointer_manager_v1 {
    Q_OBJECT

public:
    RelativePointerManager();
};

class RelativePointer;

class RelativePointerHandle : public QtWayland::zwp_relative_pointer_v1 {
public:
    RelativePointerHandle(::zwp_relative_pointer_v1 *object, RelativePointer *owner);
    ~RelativePointerHandle() override;

protected:
    void zwp_relative_pointer_v1_relative_motion(uint32_t utime_hi, uint32_t utime_lo,
                                                 wl_fixed_t dx, wl_fixed_t dy,
                                                 wl_fixed_t dx_unaccel,
                                                 wl_fixed_t dy_unaccel) override;

private:
    RelativePointer *m_owner;
};

class RelativePointer : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // True once relative motion can be delivered: running on Wayland, the
    // compositor offers zwp_relative_pointer_manager_v1, and a pointer exists.
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit RelativePointer(QObject *parent = nullptr);
    ~RelativePointer() override;

    bool available() const { return m_handle != nullptr; }

signals:
    void availableChanged();
    // Accelerated and unaccelerated deltas, in surface-local units.
    void moved(qreal dx, qreal dy, qreal unaccelDx, qreal unaccelDy);

private:
    friend class RelativePointerHandle;

    void attach();
    void detach();

    std::unique_ptr<RelativePointerManager> m_manager;
    std::unique_ptr<RelativePointerHandle> m_handle;
    wl_pointer *m_pointer = nullptr;
    QTimer m_recheck;
};
