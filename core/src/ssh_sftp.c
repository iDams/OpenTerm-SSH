#include "ssh_sftp.h"
#include "ssh_core.h"
#include "ssh_connection.h"
#include <libssh/sftp.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

term_ssh_error_t term_ssh_sftp_init(term_ssh_sftp_t **sftp, term_ssh_connection_t *conn) {
    if (!sftp || !conn || !conn->connected) {
        return TERM_SSH_ERROR;
    }
    
    return ssh_sftp_create(sftp, conn);
}

void term_ssh_sftp_free(term_ssh_sftp_t *sftp) {
    if (!sftp) {
        return;
    }
    
    if (sftp->sftp_session) {
        sftp_free(sftp->sftp_session);
        sftp->sftp_session = NULL;
    }
    
    free(sftp);
}

term_ssh_error_t term_ssh_sftp_upload(term_ssh_sftp_t *sftp, 
                                       const char *local_path, 
                                       const char *remote_path,
                                       term_ssh_progress_callback_t callback,
                                       void *userdata) {
    if (!sftp || !local_path || !remote_path) {
        return TERM_SSH_ERROR;
    }
    
    sftp_file remote_file = sftp_open(sftp->sftp_session, remote_path, 
                                       O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (!remote_file) {
        ssh_core_log(sftp->conn->session, TERM_SSH_LOG_ERROR, 
                     "No se pudo abrir archivo remoto: %s", remote_path);
        return TERM_SSH_ERROR_FILE;
    }
    
    FILE *local_file = fopen(local_path, "rb");
    if (!local_file) {
        sftp_close(remote_file);
        ssh_core_log(sftp->conn->session, TERM_SSH_LOG_ERROR, 
                     "No se pudo abrir archivo local: %s", local_path);
        return TERM_SSH_ERROR_FILE;
    }
    
    fseek(local_file, 0, SEEK_END);
    unsigned long total_size = ftell(local_file);
    fseek(local_file, 0, SEEK_SET);
    
    char buffer[4096];
    size_t bytes_read;
    unsigned long bytes_written = 0;
    
    while ((bytes_read = fread(buffer, 1, sizeof(buffer), local_file)) > 0) {
        size_t written = sftp_write(remote_file, buffer, bytes_read);
        if (written != bytes_read) {
            fclose(local_file);
            sftp_close(remote_file);
            return TERM_SSH_ERROR;
        }
        
        bytes_written += written;
        
        if (callback) {
            if (callback(bytes_written, total_size, userdata) != 0) {
                fclose(local_file);
                sftp_close(remote_file);
                return TERM_SSH_ERROR;
            }
        }
    }
    
    fclose(local_file);
    sftp_close(remote_file);
    
    ssh_core_log(sftp->conn->session, TERM_SSH_LOG_INFO, 
                 "Upload completado: %s -> %s", local_path, remote_path);
    
    return TERM_SSH_OK;
}

term_ssh_error_t term_ssh_sftp_download(term_ssh_sftp_t *sftp, 
                                         const char *remote_path, 
                                         const char *local_path,
                                         term_ssh_progress_callback_t callback,
                                         void *userdata) {
    if (!sftp || !remote_path || !local_path) {
        return TERM_SSH_ERROR;
    }
    
    sftp_file remote_file = sftp_open(sftp->sftp_session, remote_path, O_RDONLY, 0);
    if (!remote_file) {
        ssh_core_log(sftp->conn->session, TERM_SSH_LOG_ERROR, 
                     "No se pudo abrir archivo remoto: %s", remote_path);
        return TERM_SSH_ERROR_FILE;
    }
    
    FILE *local_file = fopen(local_path, "wb");
    if (!local_file) {
        sftp_close(remote_file);
        ssh_core_log(sftp->conn->session, TERM_SSH_LOG_ERROR, 
                     "No se pudo crear archivo local: %s", local_path);
        return TERM_SSH_ERROR_FILE;
    }
    
    uint64_t remote_size = 0;
    sftp_attributes attrs = sftp_stat(sftp->sftp_session, remote_path);
    if (attrs) {
        remote_size = attrs->size;
        sftp_attributes_free(attrs);
    }
    
    char buffer[4096];
    int bytes_read;
    unsigned long total_read = 0;
    
    while ((bytes_read = sftp_read(remote_file, buffer, sizeof(buffer))) > 0) {
        size_t written = fwrite(buffer, 1, bytes_read, local_file);
        if (written != (size_t)bytes_read) {
            fclose(local_file);
            sftp_close(remote_file);
            return TERM_SSH_ERROR;
        }
        
        total_read += bytes_read;
        
        if (callback) {
            callback(total_read, remote_size, userdata);
        }
    }
    
    fclose(local_file);
    sftp_close(remote_file);
    
    ssh_core_log(sftp->conn->session, TERM_SSH_LOG_INFO, 
                 "Download completado: %s -> %s", remote_path, local_path);
    
    return TERM_SSH_OK;
}

term_ssh_error_t term_ssh_sftp_list(term_ssh_sftp_t *sftp, 
                                     const char *path, 
                                     char ***files, 
                                     size_t *count) {
    if (!sftp || !path || !files || !count) {
        return TERM_SSH_ERROR;
    }
    
    sftp_dir dir = sftp_opendir(sftp->sftp_session, path);
    if (!dir) {
        return TERM_SSH_ERROR_FILE;
    }
    
    *files = NULL;
    *count = 0;
    
    sftp_attributes file;
    while ((file = sftp_readdir(sftp->sftp_session, dir)) != NULL) {
        if (strcmp(file->name, ".") != 0 && strcmp(file->name, "..") != 0) {
            char **new_files = realloc(*files, (*count + 1) * sizeof(char *));
            if (!new_files) {
                sftp_attributes_free(file);
                sftp_closedir(dir);
                return TERM_SSH_ERROR_ALLOC;
            }
            
            *files = new_files;
            (*files)[*count] = strdup(file->name);
            (*count)++;
        }
        
        sftp_attributes_free(file);
    }
    
    sftp_closedir(dir);
    
    return TERM_SSH_OK;
}

term_ssh_error_t term_ssh_sftp_mkdir(term_ssh_sftp_t *sftp, const char *path) {
    if (!sftp || !path) {
        return TERM_SSH_ERROR;
    }
    
    if (sftp_mkdir(sftp->sftp_session, path, 0755) != 0) {
        return TERM_SSH_ERROR;
    }
    
    return TERM_SSH_OK;
}

term_ssh_error_t term_ssh_sftp_remove(term_ssh_sftp_t *sftp, const char *path) {
    if (!sftp || !path) {
        return TERM_SSH_ERROR;
    }
    
    sftp_attributes attrs = sftp_stat(sftp->sftp_session, path);
    if (attrs) {
        bool is_directory = attrs->type == SSH_FILEXFER_TYPE_DIRECTORY;
        sftp_attributes_free(attrs);

        if (is_directory) {
            return sftp_rmdir(sftp->sftp_session, path) == 0 ? TERM_SSH_OK : TERM_SSH_ERROR;
        }

        return sftp_unlink(sftp->sftp_session, path) == 0 ? TERM_SSH_OK : TERM_SSH_ERROR;
    }
    
    return TERM_SSH_ERROR_FILE;
}

term_ssh_error_t term_ssh_sftp_rename(term_ssh_sftp_t *sftp, 
                                       const char *old_path, 
                                       const char *new_path) {
    if (!sftp || !old_path || !new_path) {
        return TERM_SSH_ERROR;
    }
    
    if (sftp_rename(sftp->sftp_session, old_path, new_path) != 0) {
        return TERM_SSH_ERROR;
    }
    
    return TERM_SSH_OK;
}

term_ssh_error_t ssh_sftp_create(term_ssh_sftp_t **sftp, term_ssh_connection_t *conn) {
    if (!sftp || !conn) {
        return TERM_SSH_ERROR;
    }
    
    *sftp = calloc(1, sizeof(term_ssh_sftp_t));
    if (!*sftp) {
        return TERM_SSH_ERROR_ALLOC;
    }
    
    (*sftp)->conn = conn;
    (*sftp)->sftp_session = sftp_new(conn->session->ssh);
    
    if (!(*sftp)->sftp_session) {
        free(*sftp);
        return TERM_SSH_ERROR;
    }
    
    if (sftp_init((*sftp)->sftp_session) != SSH_OK) {
        sftp_free((*sftp)->sftp_session);
        free(*sftp);
        return TERM_SSH_ERROR;
    }
    
    return TERM_SSH_OK;
}

term_ssh_error_t ssh_sftp_get_file_info(term_ssh_sftp_t *sftp, 
                                         const char *path, 
                                         uint64_t *size, 
                                         uint32_t *permissions) {
    if (!sftp || !path) {
        return TERM_SSH_ERROR;
    }
    
    sftp_attributes attrs = sftp_stat(sftp->sftp_session, path);
    if (!attrs) {
        return TERM_SSH_ERROR_FILE;
    }
    
    if (size) {
        *size = attrs->size;
    }
    
    if (permissions) {
        *permissions = attrs->permissions;
    }

    sftp_attributes_free(attrs);
    
    return TERM_SSH_OK;
}
