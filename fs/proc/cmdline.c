// SPDX-License-Identifier: GPL-2.0
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <linux/string.h>

static int cmdline_proc_show(struct seq_file *m, void *v)
{
	char *c;
	char *s;

	c = kstrdup(saved_command_line, GFP_KERNEL);
	if (!c) {
		seq_puts(m, saved_command_line);
		seq_putc(m, '\n');
	return 0;
	}

	s = strstr(c, "androidboot.verifiedbootstate=orange");
	if (s) {
		memcpy(s + 30, "green ", 6);
	}

	s = strstr(c, "androidboot.vbmeta.device_state=unlocked");
	if (s) {
		memcpy(s + 32, "locked  ", 8);
	}

	s = strstr(c, "androidboot.selinux=permissive");
	if (s) {
		memcpy(s + 20, "enforcing ", 10);
	}

	seq_printf(m, "%s\n", c);
	kfree(c);
	return 0;
}

static int __init proc_cmdline_init(void)
{
	proc_create_single("cmdline", 0, NULL, cmdline_proc_show);
	return 0;
}
fs_initcall(proc_cmdline_init);
