# -*- coding: utf-8 -*-
#
# This file is part of WaiverDB.
# Copyright © 2017 Red Hat, Inc.
#
# This copyrighted material is made available to anyone wishing to use,
# modify, copy, or redistribute it subject to the terms and conditions
# of the GNU General Public License v.2, or (at your option) any later
# version.  This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY expressed or implied, including the
# implied warranties of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE.  See the GNU General Public License for more details.  You
# should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Any Red Hat trademarks that are incorporated in the source
# code or documentation are not subject to the GNU General Public
# License and may only be used or replicated with the express permission
# of Red Hat, Inc.
"""
This module contains a set of `SQLAlchemy event`_ hooks.

To use these hooks, you must register them with SQLAlchemy
using the :func:`sqlalchemy.event.listen` function.

.. _SQLALchemy events:
    https://docs.sqlalchemy.org/en/latest/orm/events.html
"""
from __future__ import unicode_literals

from gettext import gettext as _
import logging

# fedmsg is an optional dependency and may not be present
try:
    import fedmsg
except ImportError:
    fedmsg = None

from waiverdb.models import Waiver


_log = logging.getLogger(__name__)


def fedmsg_new_waiver(session):
    """
    A post-commit event hook that emits fedmsgs.

    This event is designed to be registered with a session factory::

        >>> from sqlalchemy.event import listen
        >>> listen(MyScopedSession, 'after_commit', fedmsg_new_waiver)

    The emitted fedmsg will look like::

        {
          "username": "jcline",
          "i": 4,
          "timestamp": 1489686124,
          "msg_id": "2017-80e46243-e6f5-46df-8dcd-4d17809eb298",
          "topic": "org.fedoraproject.dev.waiverdb.waiver.new",
          "msg": {
            "comment": "Because I said so",
            "username": "http://jcline.id.fedoraproject.org/",
            "waived": true,
            "timestamp": "2017-03-16T17:42:04.209638",
            "product_version": "Satellite 6.3",
            "result_id": 1,
            "id": 15
          }
        }

    Args:
        session (sqlalchemy.orm.Session): The session that was committed to the
            database. This session is not active and cannot emit SQL.

    Raises:
        RuntimeError: If fedmsg is not installed.
    """
    _log.debug('The fedmsg_new_waiver SQLAlchemy event has been activated.')
    if fedmsg is None:
        msg = _('The application has been configured to publish fedmsgs, but '
                'fedmsg is not installed. Please install fedmsg or remove the '
                'fedmsg SQLAlchemy event handler.')
        raise RuntimeError(msg)

    for row in session.identity_map.values():
        if isinstance(row, Waiver):
            _log.debug('Publishing fedmsg for %r', row)
            fedmsg.publish(topic='waiver.new', msg=row.__json__())
