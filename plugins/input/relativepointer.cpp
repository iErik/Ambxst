#include "relativepointer.h"

#include <QGuiApplication>
#include <QLoggingCategory>
#include <QtGui/qguiapplication_platform.h>

Q_LOGGING_CATEGORY(lcRelPointer, "ambxst.input.relativepointer")

RelativePointerManager::RelativePointerManager()
    : QWaylandClientExtensionTemplate(1) {
    initialize();
}

RelativePointerHandle::RelativePointerHandle(::zwp_relative_pointer_v1 *object,
                                             RelativePointer *owner)
    : QtWayland::zwp_relative_pointer_v1(object), m_owner(owner) {}

RelativePointerHandle::~RelativePointerHandle() {
    if (isInitialized())
        destroy();
}

void RelativePointerHandle::zwp_relative_pointer_v1_relative_motion(
    uint32_t, uint32_t, wl_fixed_t dx, wl_fixed_t dy, wl_fixed_t dx_unaccel,
    wl_fixed_t dy_unaccel) {
    emit m_owner->moved(wl_fixed_to_double(dx), wl_fixed_to_double(dy),
                        wl_fixed_to_double(dx_unaccel), wl_fixed_to_double(dy_unaccel));
}

static wl_pointer *currentPointer() {
    auto *app = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>()
                        : nullptr;
    return app ? app->pointer() : nullptr;
}

RelativePointer::RelativePointer(QObject *parent) : QObject(parent) {
    if (!qGuiApp || !qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>()) {
        qCInfo(lcRelPointer) << "not running on Wayland; relative pointer unavailable";
        return;
    }

    m_manager = std::make_unique<RelativePointerManager>();
    connect(m_manager.get(), &QWaylandClientExtension::activeChanged, this, [this] {
        if (m_manager->isActive())
            attach();
        else
            detach();
    });

    // Qt recreates its wl_pointer when the seat loses and regains the pointer
    // capability (mouse unplugged, touchpad toggled). There is no public signal
    // for that, so re-check periodically and follow the current one.
    m_recheck.setInterval(2000);
    connect(&m_recheck, &QTimer::timeout, this, [this] {
        if (m_manager->isActive() && currentPointer() != m_pointer)
            attach();
    });
    m_recheck.start();

    if (m_manager->isActive())
        attach();
}

RelativePointer::~RelativePointer() {
    // Destroy the handle before the manager it was created from.
    m_handle.reset();
    m_manager.reset();
}

void RelativePointer::attach() {
    const bool wasAvailable = available();
    m_handle.reset();
    m_pointer = nullptr;

    wl_pointer *pointer = currentPointer();
    if (m_manager && m_manager->isActive() && pointer) {
        m_handle = std::make_unique<RelativePointerHandle>(
            m_manager->get_relative_pointer(pointer), this);
        m_pointer = pointer;
        qCInfo(lcRelPointer) << "relative pointer attached";
    } else if (m_manager && !m_manager->isActive()) {
        qCInfo(lcRelPointer) << "compositor lacks zwp_relative_pointer_manager_v1";
    }

    if (available() != wasAvailable)
        emit availableChanged();
}

void RelativePointer::detach() {
    const bool wasAvailable = available();
    m_handle.reset();
    m_pointer = nullptr;
    if (available() != wasAvailable)
        emit availableChanged();
}
