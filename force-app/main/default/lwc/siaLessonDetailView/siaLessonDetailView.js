import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLesson from '@salesforce/apex/SiaKnowledgeController.getLesson';
import getLessonUsageHistory from '@salesforce/apex/SiaKnowledgeController.getLessonUsageHistory';
import updateLessonText from '@salesforce/apex/SiaKnowledgeController.updateLessonText';
import updateAdminNotes from '@salesforce/apex/SiaKnowledgeController.updateAdminNotes';
import deprecateLesson from '@salesforce/apex/SiaKnowledgeController.deprecateLesson';
import removeLessonPermanently from '@salesforce/apex/SiaKnowledgeController.removeLessonPermanently';

const USAGE_COLUMNS = [
    { label: 'Session', fieldName: 'session_id__c', type: 'text' },
    { label: 'Date', fieldName: 'timestamp__c', type: 'date' },
    { label: 'Outcome', fieldName: 'outcome__c', type: 'text' },
    { label: 'Points', fieldName: 'reward_points__c', type: 'number' },
    { label: 'Helpful?', fieldName: 'lesson_was_helpful__c', type: 'boolean' }
];

export default class SiaLessonDetailView extends LightningElement {
    _lessonId;
    @track lesson = null;
    @track usageHistory = [];
    isLoading = false;
    isEditingLesson = false;
    isEditingNotes = false;
    editLessonText = '';
    editNotesText = '';
    showConfirmModal = false;
    usagePage = 0;
    noMoreUsage = false;

    usageColumns = USAGE_COLUMNS;
    _connected = false;

    connectedCallback() {
        this._connected = true;
        if (this._lessonId) {
            this.loadLesson();
            this.loadUsageHistory();
        }
    }

    @api
    get lessonId() {
        return this._lessonId;
    }
    set lessonId(value) {
        console.log('[SIA-LessonDetail] setter called with:', value);
        if (!value) return;
        this._lessonId = value;
        if (value) {
            this.loadLesson();
            this.usagePage = 0;
            this.usageHistory = [];
            this.loadUsageHistory();
        }
    }

    get statusBadgeClass() {
        const base = 'slds-badge ';
        switch (this.lesson?.status) {
            case 'Promoted': return base + 'slds-badge_success';
            case 'Active': return base + 'slds-badge_inverse';
            case 'Hidden': return base + 'slds-badge_warning';
            case 'Archived': return base + 'slds-badge_lightest';
            default: return base;
        }
    }

    get notesDisplay() {
        return this.lesson?.adminNotes || '(No notes)';
    }

    get hasUsageHistory() {
        return this.usageHistory && this.usageHistory.length > 0;
    }

    async loadLesson() {
        console.log('[SIA-LessonDetail] loadLesson called, id:', this._lessonId);
        this.isLoading = true;
        try {
            const raw = await getLesson({ lessonId: this._lessonId });
            if (raw) {
                const refs = raw.times_referenced__c || 0;
                const succs = raw.times_successful__c || 0;
                console.log('[SIA-LessonDetail] raw result:', JSON.stringify(raw).substring(0, 200));
                this.lesson = {
                    Id: raw.Id,
                    lessonText: raw.lesson_text__c || '',
                    adminNotes: raw.admin_notes__c || '',
                    confidence: raw.confidence_score__c || 0,
                    referenceCount: refs,
                    successCount: succs,
                    successRate: refs > 0 ? Math.round((succs / refs) * 100) : 0,
                    subagent: raw.topic_area__c || '',
                    categories: raw.categories__c || '',
                    status: raw.is_promoted__c ? 'Promoted'
                        : raw.is_archived__c ? 'Archived'
                        : (raw.confidence_score__c || 0) < 0.30 ? 'Hidden'
                        : 'Active',
                    createdDate: raw.CreatedDate,
                    lastValidated: raw.last_validated__c,
                    lastModifiedByAdmin: raw.last_modified_by_admin__c,
                    createdBySession: raw.created_by_session__c
                };
            }
        } catch (error) {
            console.error('[SIA-LessonDetail] loadLesson error:', error);
            this.showError('Error loading lesson', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadUsageHistory() {
        try {
            const results = await getLessonUsageHistory({ lessonId: this._lessonId, pageNumber: this.usagePage });
            if (results && results.length > 0) {
                this.usageHistory = [...this.usageHistory, ...results];
            } else {
                this.noMoreUsage = true;
            }
        } catch (error) {
            console.error('Error loading usage history', error);
        }
    }

    loadMoreUsage() {
        this.usagePage++;
        this.loadUsageHistory();
    }

    // Edit Lesson
    startEditLesson() {
        this.editLessonText = this.lesson.lessonText || '';
        this.isEditingLesson = true;
    }
    cancelEditLesson() {
        this.isEditingLesson = false;
    }
    handleLessonTextChange(event) {
        this.editLessonText = event.detail.value;
    }
    async saveLesson() {
        try {
            await updateLessonText({ lessonId: this._lessonId, newText: this.editLessonText });
            this.lesson = { ...this.lesson, lessonText: this.editLessonText };
            this.isEditingLesson = false;
            this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Lesson text saved', variant: 'success' }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: error.body?.message || 'Failed to save', variant: 'error' }));
        }
    }

    // Edit Notes
    startEditNotes() {
        this.editNotesText = this.lesson.adminNotes || '';
        this.isEditingNotes = true;
    }
    cancelEditNotes() {
        this.isEditingNotes = false;
    }
    handleNotesTextChange(event) {
        this.editNotesText = event.detail.value;
    }
    async saveNotes() {
        try {
            await updateAdminNotes({ lessonId: this._lessonId, newNotes: this.editNotesText });
            this.lesson = { ...this.lesson, adminNotes: this.editNotesText };
            this.isEditingNotes = false;
            this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Admin notes saved', variant: 'success' }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: error.body?.message || 'Failed to save', variant: 'error' }));
        }
    }

    // Deprecate
    async handleDeprecate(event) {
        const action = event.detail.value;
        try {
            await deprecateLesson({ lessonId: this._lessonId, action: action });
            this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: `Lesson ${action.toLowerCase()}d`, variant: 'success' }));
            this.loadLesson();
        } catch (error) {
            this.showError('Error deprecating lesson', error);
        }
    }

    // Remove
    handleRemoveClick() {
        console.log('[SIA-LessonDetail] Remove clicked, _lessonId:', this._lessonId, 'lesson.Id:', this.lesson?.Id);
        this.showConfirmModal = true;
    }
    cancelRemove() {
        this.showConfirmModal = false;
    }
    async confirmRemove() {
        this.showConfirmModal = false;
        const idToDelete = this.lesson ? this.lesson.Id : this._lessonId;
        console.log('[SIA-LessonDetail] confirmRemove, using ID:', idToDelete, 'from lesson.Id:', this.lesson?.Id, '_lessonId:', this._lessonId);
        if (!idToDelete) {
            this.showError('Error', { body: { message: 'No lesson ID available' } });
            return;
        }
        try {
            await removeLessonPermanently({ lessonId: idToDelete });
            console.log('[SIA-LessonDetail] delete succeeded');
            this.dispatchEvent(new ShowToastEvent({ title: 'Removed', message: 'Lesson permanently removed', variant: 'success' }));
            this.handleBack();
        } catch (error) {
            this.showError('Error removing lesson', error);
        }
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back', { detail: { refresh: true } }));
    }

    showError(title, error) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message: error?.body?.message || 'Unknown error',
            variant: 'error'
        }));
    }
}